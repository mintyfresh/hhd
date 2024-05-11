module hhd.util.memory;

/// Number of bytes in a kilobyte.
enum size_t KILOBYTE = 1024;
/// Number of bytes in a megabyte.
enum size_t MEGABYTE = 1024 * KILOBYTE;
/// Number of bytes in a gigabyte.
enum size_t GIGABYTE = 1024 * MEGABYTE;
/// Number of bytes in a terabyte.
enum size_t TERABYTE = 1024 * GIGABYTE;

pragma(inline, true)
@property
size_t kilobytes(size_t value) pure nothrow @safe @nogc
in
{
    assert(value < size_t.max / KILOBYTE, "Value is too large.");
}
do
{
    return value * KILOBYTE;
}

pragma(inline, true)
@property
size_t megabytes(size_t value) pure nothrow @safe @nogc
in
{
    assert(value < size_t.max / MEGABYTE, "Value is too large.");
}
do
{
    return value * MEGABYTE;
}

pragma(inline, true)
@property
size_t gigabytes(size_t value) pure nothrow @safe @nogc
in
{
    assert(value < size_t.max / GIGABYTE, "Value is too large.");
}
do
{
    return value * GIGABYTE;
}

pragma(inline, true)
@property
size_t terabytes(size_t value) pure nothrow @safe @nogc
in
{
    assert(value < size_t.max / TERABYTE, "Value is too large.");
}
do
{
    return value * TERABYTE;
}

// singular aliases
alias kilobyte = kilobytes;
alias megabyte = megabytes;
alias gigabyte = gigabytes;
alias terabyte = terabytes;
