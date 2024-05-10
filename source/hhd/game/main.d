module hhd.game.main;

struct GameOffscreenBuffer
{
    void* memory; // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX

    int width;
    int height;
    int pitch;
}

pragma(inline, true)
private uint
createBRGPixel(uint red, uint green, uint blue) pure nothrow @nogc
{
    return (red << 16) | (green << 8) | (blue << 0);
}

private void
renderFunkyGradient(in ref GameOffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc
{
    ubyte* row = cast(ubyte*) buffer.memory;

    foreach (y; 0..buffer.height)
    {
        uint* pixel = cast(uint*) row;

        foreach (x; 0..buffer.width)
        {
            ubyte blue  = cast(ubyte)(x + xOffset);
            ubyte green = cast(ubyte)(y + yOffset);

            *pixel++ = createBRGPixel(0, green, blue);
        }

        row += buffer.pitch;
    }
}

void
gameUpdateAndRender(in ref GameOffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc
{
    renderFunkyGradient(buffer, xOffset, yOffset);
}
