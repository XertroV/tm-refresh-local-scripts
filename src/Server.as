Net::Socket@ g_socket = null;
int g_port = 30005;
bool g_socketInitialized = false;
Net::Socket@ g_activeClient = null;
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


void Main() {
    if (g_socket !is null) {
        g_socket.Close();
        @g_socket = null;
    }
    @g_socket = Net::Socket();
    if (g_socket is null) {
        error("Failed to create socket");
        return;
    }
    if (g_socket.Listen("localhost", g_port)) {
        g_socketInitialized = true;
        trace("ManiaScript refresher socket listening on port " + g_port);
    } else {
        error("Failed to start socket server on port " + g_port);
        return;
    }
    while (g_socketInitialized && g_socket !is null) {
        yield();
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
                trace("Client connected.");
                @g_activeClient = client;
                startnew(HandleClient, client);
            }
        }
    }
    trace("Socket server loop ended.");
}

void HandleClient(ref@ userdata) {
    Net::Socket@ client = cast<Net::Socket@>(userdata);
    if (client is null) {
        error("HandleClient: Could not cast userdata.");
        if (g_activeClient is userdata) @g_activeClient = null;
        return;
    }

    g_ClientConnected = true;
    trace("HandleClient started. g_ClientConnected = true.");
    bool commandProcessed = false;

    while (g_ClientConnected) {
        yield();
        int bytes = client.Available();
        if (bytes > 0) {
            string data = client.ReadRaw(bytes);
            Json::Value@ json;
            try {
               @json = Json::Parse(data);
            } catch {
                string errMsg = "Failed to parse JSON command: " + getExceptionInfo();
                trace("Client Error: " + errMsg);
                SendClientError(errMsg);
                continue;
            }
            if (json !is null) {
                string command = json["command"];
                if (command == "refresh") {
                    if(commandProcessed) {
                        SendClientError("Refresh command already processed.");
                        continue;
                    }
                    commandProcessed = true;
                    trace("Received refresh command from client.");
                    g_DoExtra = bool(json["extra"]);
                    g_DoFilter = bool(json["filter"]);
                    g_DoTitle = bool(json["title"]);
                    ResetCount();
                    SendClientLog("Starting refresh operation...");
                    if (g_DoFilter && g_DoTitle) {
                        LoadIgnorePatternsAndRefresh();
                    } else {
                        RefreshLocalScriptFiles();
                    }
                    break; 
                } else {
                     string errMsg = "Unknown command: " + command;
                     trace("Client Error: " + errMsg);
                     SendClientError(errMsg);
                }
            } else {
                string errMsg = "Received data could not be parsed into a valid JSON object.";
                trace("Client Error: " + errMsg);
                SendClientError(errMsg);
            }
        } else {
             if (commandProcessed) {
                break;
            }
        }
    }
    trace("Client handler loop finished.");
    g_ClientConnected = false;
    if (g_activeClient is client) {
         @g_activeClient = null;
    }
    client.Close();
    trace("Client disconnected. g_ClientConnected = false.");
}

void OnDestroyed() {
    g_socketInitialized = false;
    _Unload();
}

void OnDisabled() {
    g_socketInitialized = false;
    _Unload();
}

void _Unload() {
    g_ClientConnected = false;
    if (g_activeClient !is null) {
        g_activeClient.Close();
        @g_activeClient = null;
    }
    if (g_socket !is null) {
        g_socket.Close();
        @g_socket = null;
    }
    trace("Socket server unloaded.");
}