package com.socialmedia.social.config;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.socialmedia.social.controller.FileController;
import com.socialmedia.social.service.S3StorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseBodyAdvice;

/**
 * Rewrites every raw S3 URL in an outgoing JSON response into a short-lived
 * presigned one, right before it leaves the service.
 *
 * Why here, and not in each place a response is built (PostService,
 * UserProfileService, CommentService, StatusService, ...): the bucket now
 * has Block Public Access on (see S3StorageService's doc comment / the
 * bucket console setup), so a raw https://bucket.s3.region.amazonaws.com/key
 * URL just 403s for the client — every field, on every response, anywhere
 * in the object graph, needs converting. Patching each of the 15+ DTOs
 * that carry a media URL (profilePictureUrl, coverPhotoUrl, imageUrls,
 * mediaUrl, photoUrl, ...) individually is exactly the kind of thing that's
 * easy to get right today and just as easy to silently miss the next time
 * a field or endpoint is added. Intercepting every response body once,
 * generically, means nothing can drift out of sync with this rule.
 *
 * Scope: this covers every endpoint in *this* service (posts, profiles,
 * statuses, comments, search). It does NOT cover social-chats-service's
 * message/group-photo URLs — that's a separate microservice with no S3
 * SDK wiring of its own; it just stores whatever URL string this
 * service's /files/upload handed back. It needs its own equivalent (or a
 * call back into this service) as a follow-up, not covered here.
 */
@RestControllerAdvice
@RequiredArgsConstructor
public class S3UrlPresigningAdvice implements ResponseBodyAdvice<Object> {

    private final S3StorageService s3StorageService;
    private final ObjectMapper objectMapper;

    @Override
    public boolean supports(MethodParameter returnType, Class<? extends HttpMessageConverter<?>> converterType) {
        // FileController's responses (upload/delete/check) hand back the
        // RAW, permanent URL that the client is about to store (e.g. as
        // Post.imageUrls) — that value must stay stable forever, not a
        // presigned link that expires in an hour. Everywhere else in this
        // service, a returned URL is meant for immediate display, so it's
        // fair game to presign.
        return returnType.getContainingClass() != FileController.class;
    }

    @Override
    public Object beforeBodyWrite(Object body, MethodParameter returnType, MediaType selectedContentType,
            Class<? extends HttpMessageConverter<?>> selectedConverterType, ServerHttpRequest request,
            ServerHttpResponse response) {
        if (body == null) return null;
        // A raw String/primitive return value serializes differently than
        // everything else (Spring wraps it, doesn't call this converter the
        // same way) — none of this service's endpoints return one, but
        // skip cleanly rather than risk mangling it if that ever changes.
        if (body instanceof CharSequence || body instanceof Number || body instanceof Boolean) {
            return body;
        }
        JsonNode tree = objectMapper.valueToTree(body);
        rewriteUrls(tree);
        return tree;
    }

    private void rewriteUrls(JsonNode node) {
        if (node.isObject()) {
            ObjectNode obj = (ObjectNode) node;
            var fields = obj.fields();
            while (fields.hasNext()) {
                var entry = fields.next();
                JsonNode value = entry.getValue();
                if (value.isTextual() && s3StorageService.isS3Url(value.asText())) {
                    obj.put(entry.getKey(), s3StorageService.presign(value.asText()));
                } else {
                    rewriteUrls(value);
                }
            }
        } else if (node.isArray()) {
            ArrayNode arr = (ArrayNode) node;
            for (int i = 0; i < arr.size(); i++) {
                JsonNode value = arr.get(i);
                if (value.isTextual() && s3StorageService.isS3Url(value.asText())) {
                    arr.set(i, objectMapper.getNodeFactory().textNode(s3StorageService.presign(value.asText())));
                } else {
                    rewriteUrls(value);
                }
            }
        }
    }
}
