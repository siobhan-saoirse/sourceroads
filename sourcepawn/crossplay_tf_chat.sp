#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <steamworks>


#define CHAT_POST_URL "http://26.158.225.149:7000/chat"
#define CHAT_GET_URL  "http://26.158.225.149:7000/chat"
#define GAME_NAME     "TF2"

public void OnPluginStart()
{
    HookEvent("player_say", OnPlayerSay, EventHookMode_Post);
    CreateTimer(2.0, Timer_GetChat, _, TIMER_REPEAT);
}
public void OnMapStart() {
    PrecacheSound("ambient/levels/canals/windchime5.wav",true)
}
// ---------- Chat: capture and POST ----------

// Command listener signature: (client, const char[] command, int argc)
public void OnPlayerSay(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    char text[512];
    GetEventString(event, "text", text, sizeof(text));

    TrimString(text);
    if (text[0] == '\0') return;

    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));

    // Escape quotes for safe JSON (replace " with ')

    char json[1024];
    Format(json, sizeof(json), "{\"name\":\"[TF2] %s\",\"text\":\"%s\"}", playerName, text);

    Handle req = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, CHAT_POST_URL);
    if (req == INVALID_HANDLE) return;

    SteamWorks_SetHTTPRequestHeaderValue(req, "Content-Type", "application/json");
    SteamWorks_SetHTTPRequestRawPostBody(req, "application/json", json, strlen(json));
    SteamWorks_SetHTTPCallbacks(req, OnHTTPResponse);
    SteamWorks_SendHTTPRequest(req);

    PrintToServer("[CHAT->POST] %s: %s", playerName, text);
}

public int OnHTTPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
{
    CloseHandle(hRequest);
    return 0;
}

// === Timer: fetch chat JSON from server ===
public Action Timer_GetChat(Handle timer)
{
    Handle req = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, CHAT_GET_URL);
    SteamWorks_SetHTTPRequestHeaderValue(req, "Content-Type", "application/json");
    SteamWorks_SetHTTPCallbacks(req, OnChatResponse);
    SteamWorks_SendHTTPRequest(req);
    return Plugin_Continue;
}
public int OnChatResponse(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode statusCode)
{
    if (bFailure || !bRequestSuccessful || statusCode != k_EHTTPStatusCode200OK)
        return 0;

    int bodysize = 0;
    if (!SteamWorks_GetHTTPResponseBodySize(request, bodysize) || bodysize <= 0)
    {
        PrintToServer("[SYNC] Empty HTTP response or failed to read size (size=%d)", bodysize);
        return 0;
    }

    // cap to buffer size to avoid overflow
    char body[8192];
    int maxBody = sizeof(body) - 1;
    if (bodysize > maxBody)
    {
        PrintToServer("[SYNC] HTTP body size %d larger than buffer %d - truncating", bodysize, maxBody);
        bodysize = maxBody;
    }

    // Read body safely and nul-terminate
    SteamWorks_GetHTTPResponseBodyData(request, body, bodysize);
    body[bodysize] = '\0';

    int pos = 0;
    int nameKey, textKey;

    // Parse all chat messages incrementally
    while (pos < bodysize)
    {
        nameKey = StrContains(body[pos], "\"name\":\"");
        if (nameKey == -1) break; // no more messages

        int nameStart = pos + nameKey + 8;
        int nameEnd = StrContains(body[nameStart], "\"");
        if (nameEnd == -1) break;

        char name[64];
        strcopy(name, sizeof(name), body[nameStart]);
        name[nameEnd] = '\0';

        textKey = StrContains(body[nameStart + nameEnd], "\"text\":\"");
        if (textKey == -1) break;

        int textStart = nameStart + nameEnd + textKey + 8;
        int textEnd = StrContains(body[textStart], "\"");
        if (textEnd == -1) break;

        char text[256];
        strcopy(text, sizeof(text), body[textStart]);
        text[textEnd] = '\0';
        if (StrContains(name, GAME_NAME) != -1) return 0;
        
        PrintToChatAll("%s: %s", name, text);
        EmitSoundToAll("ambient/levels/canals/windchime5.wav")

        // Move the position past this message for next iteration
        pos = textStart + textEnd + 1;
    }

    CloseHandle(request);
    return 0;
}
