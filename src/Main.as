void Main(){
}

void OnDestroyed() { _Unload(); }
void OnDisabled() { _Unload(); }
void _Unload() {
}

bool g_DoExtra = false;
bool g_DoFilter = false;
bool g_DoTitle = false;
array<string> g_RefreshIgnorePatterns;

/** Render function called every frame intended only for menu items in `UI`.
*/
void RenderMenu() {
    if (UI::MenuItem("Reload .Script.txt Files")) {
        g_DoExtra = false;
        g_DoFilter = false;
        g_DoTitle = false;
        startnew(RefreshLocalScriptFiles);
    }
    if (UI::MenuItem("Reload .Script.txt Files (Extra)")) {
        g_DoExtra = true;
        g_DoFilter = false;
        g_DoTitle = false;
        startnew(RefreshLocalScriptFiles);
    }
    if (UI::MenuItem("Reload .Script.txt Files (Extra + Filter + Title)")) {
        g_DoExtra = true;
        g_DoFilter = true;
        g_DoTitle = true;
        startnew(LoadIgnorePatternsAndRefresh);
    }
}

void LoadIgnorePatternsAndRefresh() {
    auto app = cast<CGameManiaPlanet@>(GetApp());
    string titleId = "";
    if (app !is null && app.LoadedManiaTitle !is null) {
        titleId = app.LoadedManiaTitle.IdName;
        trace("Current loaded title ID: " + titleId);
    } else {
        trace("No title loaded.");
        return;
    }

    auto titleFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("WorkTitles/" + titleId));
    if (titleFolder is null) {
        trace("Title folder not found: WorkTitles/" + titleId);
        return;
    }
    
    trace("Title folder path: " + titleFolder.FullDirName);
    
    g_RefreshIgnorePatterns.RemoveRange(0, g_RefreshIgnorePatterns.Length);
    
    bool refreshIgnoreFound = false;
    for (uint i = 0; i < titleFolder.Leaves.Length; i++) {
        auto file = cast<CSystemFidFile>(titleFolder.Leaves[i]);
        if (file.FileName == ".refreshignore") {
            refreshIgnoreFound = true;
            trace("Found .refreshignore file");
            IO::File f(file.FullFileName, IO::FileMode::Read);
            string contents = f.ReadToEnd();
            f.Close();
            
            array<string> lines = contents.Split("\n");
            for (uint j = 0; j < lines.Length; j++) {
                string line = lines[j].Trim();
                if (line.Length > 0) {
                    g_RefreshIgnorePatterns.InsertLast(line);
                }
            }
            
            string patternsStr = string::Join(g_RefreshIgnorePatterns, ", ");
            trace("Ignore patterns: " + patternsStr);
            break;
        }
    }
    
    if (!refreshIgnoreFound) {
        trace("No .refreshignore file found in title folder");
        return;
    }
    
    RefreshLocalScriptFiles();
}

void RefreshLocalScriptFiles() {
    ResetCount();
    if (g_DoExtra) trace("DOING EXTRA");
    if (g_DoTitle) trace("DOING TITLE ONLY");
    
    try {
        auto userFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("Scripts"));
        auto titlesFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("WorkTitles"));
        
        if (!g_DoTitle) {
            Fids::UpdateTree(userFolder);
            RefreshLocalScriptFolder(userFolder);
        }
        
        Fids::UpdateTree(titlesFolder);
        RefreshLocalScriptFolder(titlesFolder);
        
        NotifySuccess("Refreshed " + countFiles + " scripts while traversing " + countFolders + " folders.");
    } catch {
        NotifyError("Exception! " + getExceptionInfo());
    }
}

bool ShouldIgnoreFolder(const string &in folderPath) {
    if (!g_DoFilter || g_RefreshIgnorePatterns.Length == 0) {
        return false;
    }
    
    string normalizedPath = folderPath;
    normalizedPath = normalizedPath.Replace("\\", "/");
    
    for (uint i = 0; i < g_RefreshIgnorePatterns.Length; i++) {
        string pattern = g_RefreshIgnorePatterns[i];
        
        if (normalizedPath.Contains("/" + pattern) || normalizedPath.EndsWith("/" + pattern)) {
            trace("Filtered out folder by exact pattern: " + pattern);
            return true;
        }
        
        if (pattern.EndsWith("/*")) {
            string basePath = pattern.SubStr(0, pattern.Length - 2);
            if (normalizedPath.Contains("/" + basePath + "/")) {
                string pathAfterBase = normalizedPath.SubStr(normalizedPath.IndexOf("/" + basePath + "/") + basePath.Length + 2);
                if (pathAfterBase.IndexOf("/") < 0 || pathAfterBase.EndsWith("/")) {
                    trace("Filtered out folder by wildcard pattern: " + pattern);
                    return true;
                }
            }
        }
    }
    return false;
}

void RefreshLocalScriptFolder(CSystemFidsFolder@ folder) {
    string folderPath = folder.FullDirName;
    trace('refreshing scripts in ' + folderPath);
    
    for (uint i = 0; i < folder.Leaves.Length; i++) {
        auto item = cast<CSystemFidFile>(folder.Leaves[i]);
        if (string(item.FileName).ToLower().EndsWith(".script.txt")) {
            RefreshLocalScriptFid(item);
        }
    }
    
    for (uint i = 0; i < folder.Trees.Length; i++) {
        yield();
        auto item = cast<CSystemFidsFolder>(folder.Trees[i]);
        
        if (ShouldIgnoreFolder(item.FullDirName)) {
            trace('ignoring folder: ' + item.FullDirName);
            continue;
        }
        
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
