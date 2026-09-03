package com.socialmedia.chats.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Phase 4: incremental delta for one conversation, relative to a client-held
 * cursor (the highest message id it has already fetched). {@code nextCursor}
 * is what the client should persist and send back on the following sync
 * call; {@code hasMore} means the page was capped by the limit, so the
 * client should call again immediately with {@code nextCursor} rather than
 * wait for the next sync trigger.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ConversationSyncResponse {
    private List<MessageResponse> messages;
    private Long nextCursor;
    private boolean hasMore;
}
