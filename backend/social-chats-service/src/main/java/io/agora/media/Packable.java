package io.agora.media;

/**
 * Marker interface for objects that can marshal themselves into a ByteBuf.
 */
public interface Packable {
    void marshal(ByteBuf out);
}
