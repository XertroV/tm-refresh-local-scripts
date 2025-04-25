Net::Socket@ g_socket = null;
Net::Socket@ g_activeClient = null;

[Setting category="General" name="Socket Connection Port" description="Port used by the plugin to listen on a TCP socket. If changed the plugin will need to be restarted."]
int SocketPort = 30005;

bool g_socketInitialized = false;
bool g_ClientConnected = false;


void SendClientMessage(Json::Value@ message) {
    if (!g_ClientConnected || g_activeClient is null) {
        return;
    }
    Net::Socket@ clientToSendTo = g_activeClient;
    try {
        clientToSendTo.Write(Json::Write(message));
    } catch {
        trace("SendClientMessage failed: " + getExceptionInfo());
    }
}

void SendClientLog(const string &in logMessage) {
    Json::Value msg = Json::Object();
    msg["status"] = "log";
    msg["message"] = logMessage;
    SendClientMessage(msg);
}

void SendClientFilter(const string &in pattern, const string &in folder) {
    Json::Value msg = Json::Object();
    msg["status"] = "filter";
    msg["pattern"] = pattern;
    msg["folder"] = folder;
    SendClientMessage(msg);
}

void SendClientError(const string &in errorMessage) {
    Json::Value msg = Json::Object();
    msg["status"] = "error";
    msg["message"] = errorMessage;
    SendClientMessage(msg);
}

void SendClientSuccess(const string &in successMessage, uint files, uint folders) {
    Json::Value msg = Json::Object();
    msg["status"] = "success";
    msg["message"] = successMessage;
    msg["files"] = files;
    msg["folders"] = folders;
    SendClientMessage(msg);
}

void InitializeServer() {
    if (g_socket !is null) {
        g_socket.Close();
        @g_socket = null;
    }
    @g_socket = Net::Socket();
    if (g_socket is null) {
        error("Failed to create socket");
        return;
    }
    if (g_socket.Listen("localhost", SocketPort)) {
        g_socketInitialized = true;
        trace("Socket server listening on port " + SocketPort + " for title: " + g_CurrentTitleId);
    } else {
        error("Failed to start socket server on port " + SocketPort);
        return;
    }
}

void UpdateServer() {
    if (!g_socketInitialized || g_socket is null) return;
    
    Net::Socket@ client = g_socket.Accept();
    if (client !is null) {
        if (g_activeClient !is null) {
            trace("Busy handling another client. Closing new connection.");
            Json::Value busyResponse = Json::Object();
            busyResponse["status"] = "error";
            busyResponse["message"] = "Server busy, please try again later.";
            client.Write(Json::Write(busyResponse));
            client.Close();
        } else {
            @g_activeClient = client;
            startnew(HandleClient, client);
        }
    }
}

void HandleClient(ref@ userdata) {
    Net::Socket@ client = cast<Net::Socket@>(userdata);
    if (client is null) {
        error("HandleClient: Could not cast userdata.");
        if (g_activeClient is userdata) @g_activeClient = null;
        return;
    }

    g_ClientConnected = true;
    trace("Socket client connected.");
    bool commandProcessed = false;
    
    yield();
    
    while (g_ClientConnected) {
        int bytes = client.Available();
        if (bytes <= 0) {
            trace("No command received. Closing connection.");
            break;
        }

        string data = client.ReadRaw(bytes);
        Json::Value@ json = ParseClientData(data);
        if (json is null) {
            trace("JSON validation failed. Closing connection.");
            break;
        }

        ProcessCommand(json, commandProcessed);
        break;
    }

    CloseClientConnection(client);
}

Json::Value@ ParseClientData(const string &in data) {
    Json::Value@ json = Json::Parse(data);
    
    if (json is null || json.GetType() != Json::Type::Object) {
        SendClientError("Invalid JSON: Must be an object");
        return null;
    }
    
    if (!json.HasKey("command") || json["command"].GetType() != Json::Type::String) {
        SendClientError("Invalid JSON: Missing or invalid 'command' field");
        return null;
    }
    
    string command = string(json["command"]);
    
    if (command == "refresh") {
        if (!ValidateRefreshParams(json)) {
            return null;
        }
    }
    trace(Json::Write(json, true));
    return json;
}

bool ValidateRefreshParams(Json::Value@ json) {
    array<string> allowedParams = {"DoExtra", "DoFilter", "DoDevTitleOnly"};
    dictionary params;
    
    for (uint i = 0; i < allowedParams.Length; i++) {
        params[allowedParams[i]] = true;
    }
    
    array<string> keys = json.GetKeys();
    for (uint i = 0; i < keys.Length; i++) {
        if (keys[i] == "command") continue;
        
        if (!params.Exists(keys[i])) {
            SendClientError("Unknown parameter: " + keys[i]);
            return false;
        }
        
        if (json[keys[i]].GetType() != Json::Type::Boolean) {
            SendClientError("Parameter must be boolean: " + keys[i]);
            return false;
        }
    }
    
    for (uint i = 0; i < allowedParams.Length; i++) {
        if (!json.HasKey(allowedParams[i])) {
            json[allowedParams[i]] = false;
        }
    }
    
    return true;
}



bool ProcessCommand(Json::Value@ json, bool &out commandProcessed) {
    string command = string(json["command"]);
    
    if (command == "refresh") {
        if (commandProcessed) return false;
        
        commandProcessed = true;
        g_DoExtra = bool(json["DoExtra"]);
        g_DoFilter = bool(json["DoFilter"]);
        g_DoDevTitleOnly = bool(json["DoDevTitleOnly"]);
        
        SendClientLog("Starting refresh operation...");
        if (g_DoFilter && g_DoDevTitleOnly) {
            LoadIgnorePatternsAndRefresh();
        } else {
            RefreshLocalScriptFiles();
        }
        
        return true;
    } else {
        string errMsg = "Unknown command: " + command;
        trace("Client Error: " + errMsg);
        SendClientError(errMsg);
        return false;
    }
}

void CloseClientConnection(Net::Socket@ client) {
    g_ClientConnected = false;
    if (g_activeClient is client) {
        @g_activeClient = null;
    }
    client.Close();
    trace("Socket client disconnected.");
}

void ServerShutdown() {
    g_socketInitialized = false;
    g_ClientConnected = false;
    if (g_activeClient !is null || g_socket !is null) {
        trace("Socket server shutting down...");
    }
    if (g_activeClient !is null) {
        g_activeClient.Close();
        @g_activeClient = null;
    }
    if (g_socket !is null) {
        g_socket.Close();
        @g_socket = null;
    }
}