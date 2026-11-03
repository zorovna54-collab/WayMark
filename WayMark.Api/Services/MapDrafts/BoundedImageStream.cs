namespace WayMark.Api.Services.MapDrafts;

// Provider cannot bypass the upload limit by seeking. Does not own the HTTP stream.
internal sealed class BoundedImageStream(Stream inner) : Stream
{
    private long read;
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => read; set => throw new NotSupportedException(); }
    public override int Read(byte[] buffer, int offset, int count) => Count(inner.Read(buffer, offset, Limit(count)));
    public override int Read(Span<byte> buffer) => Count(inner.Read(buffer[..Limit(buffer.Length)]));
    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        => Count(await inner.ReadAsync(buffer[..Limit(buffer.Length)], cancellationToken));
    public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        => ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();
    private int Limit(int requested) => (int)Math.Min(requested, MapImageRules.MaxBytes - read + 1);
    private int Count(int count)
    {
        read += count;
        if (read > MapImageRules.MaxBytes) throw new DraftOperationException(413, "image_too_large", "Image exceeds 10 MiB");
        return count;
    }
    public override void Flush() => throw new NotSupportedException();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
