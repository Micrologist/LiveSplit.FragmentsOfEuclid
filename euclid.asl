//Fragments of Euclic Autosplitter
//by Micrologist & Ero

state("FragmentsofEuclid") {}

startup
{
	vars.Dbg = (Action<dynamic>) ((output) => print("[FoE ASL] " + output.ToString()));
	vars.TimerReset = (LiveSplit.Model.Input.EventHandlerT<TimerPhase>) ((s, e) =>
	{
		vars.KnownPuzzlesDone = 0;
		vars.HasLeftIntro = false;
	});
	timer.OnReset += vars.TimerReset;
	vars.TimerReset(null, timer.CurrentPhase);

	vars.SigsFound = false;
}

init
{
	bool Is64Bit = game.Is64Bit();

	vars.SigThread = new Thread(() =>
	{
		vars.Dbg("Starting signature thread.");
		vars.TokenSource = new CancellationTokenSource();
		var FoEModule = modules.First();
		var FoEScanner = new SignatureScanner(game, FoEModule.BaseAddress, FoEModule.ModuleMemorySize);

		var PortalManager = IntPtr.Zero;
		var PortalManagerSig =
			Is64Bit
			? new SigScanTarget("4C 89 25 ???????? 48 83") { OnFound = (p, s, ptr) => IntPtr.Add(ptr + 7, p.ReadValue<int>(ptr + 3)) }
			: new SigScanTarget(9, "55 8B EC 8B 45 ?? 8B 04 85 ???????? 5D C3 CC 55 8B EC 8B 45 ?? 8B 4D ?? 89") { OnFound = (p, s, ptr) => p.ReadPointer(ptr) + 4 };

		var SceneManager = IntPtr.Zero;
		var SceneManagerSig =
			Is64Bit
			? new SigScanTarget("48 8B 3D ???????? 33 DB 48 8B F1 39") { OnFound = (p, s, ptr) => IntPtr.Add(ptr + 7, p.ReadValue<int>(ptr + 3)) }
			: new SigScanTarget(1, "A1 ???????? 56 57 33 F6") { OnFound = (p, s, ptr) => p.ReadPointer(ptr) };

		var Token = vars.TokenSource.Token;
		while (!Token.IsCancellationRequested)
		{
			if (PortalManager == IntPtr.Zero && (PortalManager = FoEScanner.Scan(PortalManagerSig)) != IntPtr.Zero)
				vars.Dbg("Found PortalManager: 0x" + PortalManager.ToString("X"));

			if (SceneManager == IntPtr.Zero && (SceneManager = FoEScanner.Scan(SceneManagerSig)) != IntPtr.Zero)
				vars.Dbg("Found SceneManager: 0x" + SceneManager.ToString("X"));

			if (!(vars.SigsFound = new[] { PortalManager, SceneManager }.All(ptr => ptr != IntPtr.Zero)))
			{
				Thread.Sleep(2000);
				FoEScanner.Address = FoEModule.BaseAddress;
				FoEScanner.Size = FoEModule.ModuleMemorySize;
				continue;
			}
			else
			{
				Func<int[], DeepPointer> dPtrArr = (finalOffsets) =>
				{
					var baseOffsets = Is64Bit ? new[] { 0x48, 0x4A0, 0x0, 0x18, 0x0 } : new[] { 0x194, 0x38, 0xED0, 0xC, 0x0 };
					return new DeepPointer(PortalManager, baseOffsets.Concat(finalOffsets).ToArray());
				};
				Func<int, DeepPointer> dPtr = (finalOffset) => dPtrArr(new[] { finalOffset });

				var SpawnMessagePtr = dPtrArr(Is64Bit ? new[] { 0xF8, 0x14 } : new[] { 0x7C, 0xC });
				var NumPuzzleCompletePtr = dPtr(Is64Bit ? 0x1E0 : 0x118);
				// var FinishGamePtr = dPtr(Is64Bit ? 0x1E4 : 0x11C);
				// var LastCameraLocationPtr = dPtr(Is64Bit ? 0x200 : 0x138);
				var SpawnMessageTimerPtr = dPtr(Is64Bit ? 0x214 : 0x14C);
				var CurrentMusicPtr = dPtr(Is64Bit ? 0x268 : 0x1A0);

				vars.Watchers = new MemoryWatcherList
				{
					new StringWatcher(SpawnMessagePtr, 128) { Name = "SpawnMessage" },
					new MemoryWatcher<int>(NumPuzzleCompletePtr) { Name = "NumPuzzleComplete" },
					// new MemoryWatcher<bool>(FinishGamePtr) { Name = "FinishGame" },
					// new MemoryWatcher<Vector3f>(LastCameraLocationPtr) { Name = "LastCameraLocation" },
					new MemoryWatcher<float>(SpawnMessageTimerPtr) { Name = "SpawnMessageTimer" },
					new MemoryWatcher<int>(CurrentMusicPtr) { Name = "CurrentMusic" }
				};

				Func<string, string> PathToName = (path) =>
				{
					if (String.IsNullOrEmpty(path)) return null;

					int from = path.LastIndexOf('/') + 1;
					int to = path.LastIndexOf(".unity");
					return path.Substring(from, to - from);
				};

				old.Scene = "";
				vars.UpdateScene = (Action) (() =>
				{
					string path = new DeepPointer(SceneManager, Is64Bit ? 0x28 : 0x14, Is64Bit ? 0x8 : 0x4, 0x0).DerefString(game, 256);
					current.Scene = PathToName(path) ?? old.Scene;
				});
				break;
			}
		}

		vars.Dbg("Exiting signature thread.");
	});
	vars.SigThread.Start();
}

update
{
	if (!vars.SigsFound) return false;
	vars.Watchers.UpdateAll(game);

	vars.UpdateScene();
	current.SpawnMsg = vars.Watchers["SpawnMessage"].Current;
	current.PuzzlesDone = vars.Watchers["NumPuzzleComplete"].Current;
	current.MsgTimer = vars.Watchers["SpawnMessageTimer"].Current;
	current.Music = vars.Watchers["CurrentMusic"].Current;

	if (timer.CurrentPhase == TimerPhase.Running && !vars.HasLeftIntro && current.SpawnMsg != "Relativity" && !String.IsNullOrEmpty(current.SpawnMsg))
		vars.HasLeftIntro = true;
}

start
{
	return !vars.HasLeftIntro && old.MsgTimer > current.MsgTimer && current.MsgTimer < 0.1f;
}

split
{
	if (current.PuzzlesDone > vars.KnownPuzzlesDone)
	{
		vars.KnownPuzzlesDone = current.PuzzlesDone;
		return true;
	}

	return old.Music == 1 && current.Music == 0 && current.Scene == "EndingTest";
}

reset
{
	return !vars.HasLeftIntro && old.MsgTimer > current.MsgTimer && current.MsgTimer < 0.1f ||
	       old.Scene != "TitleScene2" && current.Scene == "TitleScene2";
}

exit
{
	vars.TokenSource.Cancel();
}

shutdown
{
	vars.TokenSource.Cancel();
	timer.OnReset -= vars.TimerReset;
}
