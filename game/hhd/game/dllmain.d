module game.hhd.game.dllmain;

version (Windows)
{
    import core.sys.windows.windows;
    import core.sys.windows.dll;

    mixin SimpleDllMain;
}
