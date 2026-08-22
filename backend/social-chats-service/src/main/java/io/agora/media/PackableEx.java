package io.agora.media;

/**
 * Packable with both marshal and unmarshal directions.
 */
public interface PackableEx extends Packable {
    void unmarshal(ByteBuf in);
}
