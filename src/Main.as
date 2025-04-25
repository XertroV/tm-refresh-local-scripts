bool g_DoExtra = false;
bool g_DoFilter = false;
bool g_DoDevTitleOnly = false;
bool g_TitleLoaded = false;
string g_CurrentTitleId = "";
array<string> g_RefreshIgnorePatterns;
CTrackMania@ app;

void Main() {
    @app = cast<CTrackMania@>(GetApp());
    
    while (true) {
        yield();
        g_CurrentTitleId = app.LoadedManiaTitle !is null ? app.LoadedManiaTitle.IdName : g_CurrentTitleId;
        g_TitleLoaded = app.LoadedManiaTitle !is null && app.ManiaTitleEditionScriptAPI !is null;
        
        if (g_TitleLoaded && (!g_socketInitialized || g_socket is null)) InitializeServer();
        if (g_socketInitialized && g_socket !is null) UpdateServer();
        if (!g_TitleLoaded) ServerShutdown();
    }
}

void RenderMenu() {
    if (g_socket !is null) UI::TextDisabled("\\$070" + Icons::Refresh + " \\$zRefresh Local Scripts Port: " + SocketPort);
    if (UI::BeginMenu(Icons::Refresh + " Refresh Local Scripts")) {
        if (UI::MenuItem("Reload .Script.txt Files")) {
            g_DoExtra = false;
            g_DoFilter = false;
            g_DoDevTitleOnly = false;
            startnew(RefreshLocalScriptFiles);
        }
        if (UI::MenuItem("Reload .Script.txt Files (Extra)")) {
            g_DoExtra = true;
            g_DoFilter = false;
            g_DoDevTitleOnly = false;
            startnew(RefreshLocalScriptFiles);
        }
        if (g_TitleLoaded && UI::MenuItem("Reload .Script.txt Files (Extra + Filter + TitleOnly)")) {
            g_DoExtra = true;
            g_DoFilter = true;
            g_DoDevTitleOnly = true;
            startnew(LoadIgnorePatternsAndRefresh);
        }
        UI::EndMenu();
    }
}


void LoadIgnorePatternsAndRefresh() {
    if (!g_TitleLoaded) {
        trace("No title loaded, cannot load ignore patterns");
        return;
    }
    string titleId = app.LoadedManiaTitle.IdName;
    string logMsg = "Current loaded title ID: " + titleId;
    trace(logMsg);
    SendClientLog(logMsg);

    CSystemFidsFolder@ titleFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("WorkTitles/" + titleId));
    if (titleFolder is null) {
        string errMsg = "Title folder not found: WorkTitles/" + titleId;
        trace(errMsg);
        SendClientError(errMsg);
        return;
    }
    Fids::UpdateTree(titleFolder);
    string pathMsg = "Title folder path: " + titleFolder.FullDirName;
    trace(pathMsg);
    SendClientLog(pathMsg);
    g_RefreshIgnorePatterns.RemoveRange(0, g_RefreshIgnorePatterns.Length);
    bool refreshIgnoreFound = false;
    for (uint i = 0; i < titleFolder.Leaves.Length; i++) {
        auto file = cast<CSystemFidFile>(titleFolder.Leaves[i]);
        if (file !is null && file.FileName == ".refreshignore") {
            refreshIgnoreFound = true;
            trace("Found .refreshignore file");
            SendClientLog("Found .refreshignore file");
            try {
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
                string patternLog = "Ignore patterns: " + patternsStr;
                trace(patternLog);
                SendClientLog(patternLog);
            } catch {
                 string errMsg = "Error reading .refreshignore: " + getExceptionInfo();
                 trace(errMsg);
                 SendClientError(errMsg);
            }
            break;
        }
    }
    if (!refreshIgnoreFound) {
         string warnMsg = "No .refreshignore file found in title folder";
         trace(warnMsg);
         SendClientLog("WARN: " + warnMsg);
         return;
    }
    RefreshLocalScriptFiles();
}

void RefreshLocalScriptFiles() {
    ResetCount();
    if (g_DoExtra) { trace("DOING EXTRA"); SendClientLog("DOING EXTRA"); }
    if (g_DoDevTitleOnly) { trace("DOING TITLE ONLY"); SendClientLog("DOING LOADED TITLE WORKTITLES FOLDER ONLY"); }
    try {
        auto userFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("Scripts"));
        auto titlesFolder = cast<CSystemFidsFolder>(Fids::GetUserFolder("WorkTitles"));
        
        if (!g_DoDevTitleOnly) {
            Fids::UpdateTree(userFolder);
            RefreshLocalScriptFolder(userFolder);
        }
        
        Fids::UpdateTree(titlesFolder);
        RefreshLocalScriptFolder(titlesFolder);
        
        string summary = "Refreshed " + countFiles + " scripts while traversing " + countFolders + " folders.";
        NotifySuccess(summary);
        SendClientSuccess(summary, countFiles, countFolders);
    } catch {
        string errMsg = "Exception! " + getExceptionInfo();
        NotifyError(errMsg);
        SendClientError(errMsg);
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
            trace("Filter pattern: [" + pattern + "] applied for: " + folderPath);
            SendClientFilter(pattern, folderPath);
            return true;
        }
    }
    return false;
}

void RefreshLocalScriptFolder(CSystemFidsFolder@ folder) {
    string folderPath = folder.FullDirName;
    string logMsg = "Refreshing scripts in " + folderPath;
    trace(logMsg);
    SendClientLog(logMsg);
    for (uint i = 0; i < folder.Leaves.Length; i++) {
        auto item = cast<CSystemFidFile>(folder.Leaves[i]);
        if (item !is null && string(item.FileName).ToLower().EndsWith(".script.txt")) {
            RefreshLocalScriptFid(item);
        }
    }
    
    for (uint i = 0; i < folder.Trees.Length; i++) {
        yield();
        auto item = cast<CSystemFidsFolder>(folder.Trees[i]);
        if (item is null) continue;
        if (ShouldIgnoreFolder(item.FullDirName)) {
            continue;
        }
        RefreshLocalScriptFolder(item);
        CountFolder();
    }
}


void RefreshLocalScriptFid(CSystemFidFile@ fid) {
    //string logMsgStart = "Refreshing script: " + fid.FileName;
    //trace(logMsgStart);
    //SendClientLog(logMsgStart);
    auto text = cast<CPlugFileTextScript>(Fids::Preload(fid));
    if (text !is null) {
        try {
            text.ReGenerate();
            if (g_DoExtra) {
                IO::File f(fid.FullFileName, IO::FileMode::Read);
                text.Text = f.ReadToEnd();
                f.Close();
            }
            CountFile();
            string logMsg = "Refreshed: " + fid.FileName;
            trace(logMsg);
            SendClientLog(logMsg);
        } catch {
             string errMsg = "Error refreshing " + fid.FileName + ": " + getExceptionInfo();
             NotifyError(errMsg);
             SendClientError(errMsg);
        }
    } else {
        string warnMsg = "Null script!? " + fid.FileName;
        NotifyWarning(warnMsg);
        SendClientLog("WARN: " + warnMsg);
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

void OnDestroyed() {
    _Unload();
}

void OnDisabled() {
    _Unload();
}

void _Unload() {
    ServerShutdown();
}