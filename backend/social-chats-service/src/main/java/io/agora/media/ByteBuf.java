package io.agora.media;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Map;
import java.util.TreeMap;

/**
 * Minimal little-endian byte buffer helper used by the Agora AccessToken2 builder.
 */
public class ByteBuf {
    private ByteBuffer buffer = ByteBuffer.allocate(1024).order(ByteOrder.LITTLE_ENDIAN);

    public ByteBuf() {
    }

    public ByteBuf(byte[] bytes) {
        this.buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
    }

    public byte[] asBytes() {
        byte[] out = new byte[buffer.position()];
        buffer.rewind();
        buffer.get(out, 0, out.length);
        return out;
    }

    private void ensureCapacity(int additional) {
        if (buffer.remaining() >= additional) {
            return;
        }
        int newCapacity = Math.max(buffer.capacity() * 2, buffer.position() + additional);
        ByteBuffer newBuffer = ByteBuffer.allocate(newCapacity).order(ByteOrder.LITTLE_ENDIAN);
        buffer.flip();
        newBuffer.put(buffer);
        buffer = newBuffer;
    }

    public ByteBuf put(short v) {
        ensureCapacity(Short.BYTES);
        buffer.putShort(v);
        return this;
    }

    public ByteBuf put(int v) {
        ensureCapacity(Integer.BYTES);
        buffer.putInt(v);
        return this;
    }

    public ByteBuf put(long v) {
        ensureCapacity(Long.BYTES);
        buffer.putLong(v);
        return this;
    }

    /**
     * Writes a length-prefixed byte array (length as unsigned short).
     */
    public ByteBuf put(byte[] v) {
        if (v == null) {
            v = new byte[0];
        }
        ensureCapacity(Short.BYTES + v.length);
        put((short) v.length);
        buffer.put(v);
        return this;
    }

    public ByteBuf put(String v) {
        byte[] bytes = v == null ? new byte[0] : v.getBytes();
        return put(bytes);
    }

    public ByteBuf put(TreeMap<Short, String> extra) {
        put((short) extra.size());
        for (Map.Entry<Short, String> pair : extra.entrySet()) {
            put(pair.getKey());
            put(pair.getValue());
        }
        return this;
    }

    public ByteBuf putIntMap(TreeMap<Short, Integer> extra) {
        put((short) extra.size());
        for (Map.Entry<Short, Integer> pair : extra.entrySet()) {
            put(pair.getKey());
            put(pair.getValue());
        }
        return this;
    }

    /**
     * Append raw bytes without a length prefix (used internally for signature+payload concatenation).
     */
    public ByteBuf putRaw(byte[] data) {
        if (data == null) {
            return this;
        }
        ensureCapacity(data.length);
        buffer.put(data);
        return this;
    }

    public short readShort() {
        return buffer.getShort();
    }

    public int readInt() {
        return buffer.getInt();
    }

    public long readLong() {
        return buffer.getLong();
    }

    public byte[] readBytes() {
        short length = readShort();
        byte[] bytes = new byte[length];
        buffer.get(bytes);
        return bytes;
    }

    public String readString() {
        byte[] bytes = readBytes();
        return new String(bytes);
    }

    public TreeMap<Short, String> readMap() {
        TreeMap<Short, String> map = new TreeMap<>();
        short length = readShort();
        for (short i = 0; i < length; ++i) {
            short k = readShort();
            String v = readString();
            map.put(k, v);
        }
        return map;
    }

    public TreeMap<Short, Integer> readIntMap() {
        TreeMap<Short, Integer> map = new TreeMap<>();
        short length = readShort();
        for (short i = 0; i < length; ++i) {
            short k = readShort();
            int v = readInt();
            map.put(k, v);
        }
        return map;
    }
}
