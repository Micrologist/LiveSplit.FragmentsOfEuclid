state("FragmentsOfEuclid")
{ 
    string250 map : 0x01345260, 0x28, 0x8, 0x0;
}

startup
{
    vars.portalManagerTarget = new SigScanTarget("48 C7 86 88 00 00 00 00 00 00 00 B8 ?? ?? ?? ?? 48 89 30 B9 ?? ?? ?? ?? 48 83 EC 20");
    /*
    PortalManager:Awake+15b - 48 C7 86 88000000 00000000 - mov qword ptr [rsi+00000088],00000000
    PortalManager:Awake+166 - B8 C0BCB304           - mov eax,04B3BCC0 <-- Pointer
    PortalManager:Awake+16b - 48 89 30              - mov [rax],rsi
    PortalManager:Awake+16e - B9 E0F6FD13           - mov ecx,13FDF6E0
    PortalManager:Awake+173 - 48 83 EC 20           - sub rsp,20
    */
    vars.scanCooldown = new Stopwatch();
    vars.startAndReset = false;
    vars.doSplit = false;
    vars.knownCompletedPuzzles = 0;
    vars.hasLeftIntro = false;
}

init
{
    var portalInstancePtr = IntPtr.Zero;

    if(!vars.scanCooldown.IsRunning)
    {
        vars.scanCooldown.Start(); 
    }

     if(vars.scanCooldown.Elapsed.TotalMilliseconds >= 1000) 
    {
        print("scanning");
        foreach (var page in game.MemoryPages(true))
        {
            var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
            portalInstancePtr = scanner.Scan(vars.portalManagerTarget);
            if(portalInstancePtr != IntPtr.Zero)
                break;
        }

        if(portalInstancePtr == IntPtr.Zero) 
        {
            vars.scanCooldown.Restart();
            throw new Exception("pointers not found - resetting");
        }
        else 
        {
            vars.scanCooldown.Reset();
        }
    }
    else 
    {
        throw new Exception("init not ready");
    }

    print((portalInstancePtr+0xC).ToString("X16"));
    var finishGameDP = new DeepPointer(portalInstancePtr+0xC, DeepPointer.DerefType.Bit32, 0x0, 0x1E4);
    vars.finishGame = new MemoryWatcher<bool>(finishGameDP);
    var lastCamPosDP = new DeepPointer(portalInstancePtr+0xC, DeepPointer.DerefType.Bit32, 0x0, 0x200);
    vars.lastCamPos = new MemoryWatcher<int>(lastCamPosDP);
    var spawnMessageDP = new DeepPointer(portalInstancePtr+0xC, DeepPointer.DerefType.Bit32, 0x0, 0x88, 0x20, 0x14);
    vars.spawnMsg = new StringWatcher(spawnMessageDP, 200);
    var spawnTimerDP = new DeepPointer(portalInstancePtr+0xC, DeepPointer.DerefType.Bit32, 0x0, 0x214);
    vars.spawnTimer = new MemoryWatcher<float>(spawnTimerDP);
    var currentMusicDP = new DeepPointer(portalInstancePtr+0xC, DeepPointer.DerefType.Bit32, 0x0, 0x268);
    vars.currentMusic = new MemoryWatcher<int>(currentMusicDP);
    var numPuzzleCompleteDP = new DeepPointer(portalInstancePtr+0xC, DeepPointer.DerefType.Bit32, 0x0, 0x1E0);
    vars.puzzlesCompleted = new MemoryWatcher<int>(numPuzzleCompleteDP);
    vars.watchers = new MemoryWatcherList() {vars.finishGame, vars.lastCamPos, vars.spawnMsg, vars.spawnTimer, vars.currentMusic, vars.puzzlesCompleted};
}

update
{
    vars.watchers.UpdateAll(game);
    vars.startAndReset = (vars.spawnMsg.Current == "Relativity" && vars.spawnTimer.Current < vars.spawnTimer.Old && !vars.hasLeftIntro);

    vars.doSplit = vars.puzzlesCompleted.Current > vars.knownCompletedPuzzles;
    if(vars.doSplit)
        vars.knownCompletedPuzzles = vars.puzzlesCompleted.Current;

    if(!vars.hasLeftIntro && !String.IsNullOrEmpty(vars.spawnMsg.Current) && vars.spawnMsg.Current != "Relativity")
        vars.hasLeftIntro = true;
}

split
{
    return (vars.currentMusic.Current == 0 && vars.currentMusic.Old == 1 && current.map == "Assets/Scenes/EndingTest.unity") || vars.doSplit;
}

start
{
    vars.knownCompletedPuzzles = 0;
    vars.hasLeftIntro = false;
    return vars.startAndReset;
}

reset
{
    return vars.startAndReset || current.map == "Assets/Scenes/TitleScene2.unity";
}
