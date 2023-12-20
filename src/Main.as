void Main(){
}

void OnDestroyed() { _Unload(); }
void OnDisabled() { _Unload(); }
void _Unload() {
}

bool g_DoExtra = false;

/** Render function called every frame intended only for menu items in `UI`.
*/
void RenderMenu() {
    if (UI::MenuItem("Reload .Script.txt Files")) {
        g_DoExtra = false;
        startnew(RefreshLocalScriptFiles);
    }
    if (UI::MenuItem("Reload .Script.txt Files (Extra)")) {
        g_DoExtra = true;
        startnew(RefreshLocalScriptFiles);
    }
}

void RefreshLocalScriptFiles() {
    ResetCount();
    if (g_DoExtra) trace("DOING EXTRA");
    try {
        auto userFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("Scripts"));
        auto titlesFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("WorkTitles"));
        Fids::UpdateTree(userFolder);
        Fids::UpdateTree(titlesFolder);
        RefreshLocalScriptFolder(userFolder);
        RefreshLocalScriptFolder(titlesFolder);
        NotifySuccess("Refreshed " + countFiles + " scripts while traversing " + countFolders + " folders.");
    } catch {
        NotifyError("Exception! " + getExceptionInfo());
    }
}

void RefreshLocalScriptFolder(CSystemFidsFolder@ folder) {
    trace('refreshing scripts in ' + folder.FullDirName);
    for (uint i = 0; i < folder.Leaves.Length; i++) {
        auto item = cast<CSystemFidFile>(folder.Leaves[i]);
        if (string(item.FileName).ToLower().EndsWith(".script.txt")) {
            RefreshLocalScriptFid(item);
        }
    }
    for (uint i = 0; i < folder.Trees.Length; i++) {
        yield();
        auto item = cast<CSystemFidsFolder>(folder.Trees[i]);
        RefreshLocalScriptFolder(item);
        CountFolder();
    }
}

void RefreshLocalScriptFid(CSystemFidFile@ fid) {
    trace("Refreshing script: " + fid.FileName);
    auto text = cast<CPlugFileTextScript>(Fids::Preload(fid));
    if (text !is null) {
        text.ReGenerate();
        if (g_DoExtra) {
            IO::File f(fid.FullFileName, IO::FileMode::Read);
            text.Text = f.ReadToEnd();
            f.Close();
        }
        CountFile();
    } else {
        NotifyWarning("Null script!? " + fid.FileName);
    }
}

uint countFiles = 0;
uint countFolders = 0;

void CountFile() {
    countFiles++;
}
void CountFolder() {
    countFolders++;
}
void ResetCount() {
    countFiles = 0;
    countFolders = 0;
}
