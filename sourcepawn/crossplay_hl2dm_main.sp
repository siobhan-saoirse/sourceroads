#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <steamworks>

#define SOCKET_URL "http://localhost:2635/update_css"
#define MAX_JSON_LEN 32768
#define MAX_SCENE_NAME 128
char g_sceneVcd[128][MAXPLAYERS + 1];

Handle gH_GetWorldModel = null;

public void OnPluginStart()
{
}

public void OnMapStart()
{
    PrintToServer("[Socket.IO] Position sync started"); 
    CreateTimer(0.1, Timer_SendAllPlayers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Command_Fly(int client, int args)
{
	if (GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, MOVETYPE_NOCLIP);
	}
	else
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
	return Plugin_Handled;
}

public Action Timer_SendAllPlayers(Handle timer)
{
    char json[MAX_JSON_LEN];
    json[0] = '\0';

    StrCat(json, sizeof(json), "{\"event\":\"update\",\"players\":[");

    bool first = true;
    int playerCount = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
            continue;

        float pos[3], ang[3];
        GetClientAbsOrigin(client, pos);
        GetClientAbsAngles(client, ang);

        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));

        char name2[MAX_NAME_LENGTH];
        Format(name2, sizeof(name2), "cs_%s", name);

        char model[PLATFORM_MAX_PATH];
        GetClientModel(client, model, sizeof(model));

        int skin = GetEntProp(client, Prop_Send, "m_nSkin");
        int seq = GetEntProp(client, Prop_Send, "m_nSequence");
        char anim[16];
        IntToString(seq, anim, sizeof(anim));

        char weaponModel[PLATFORM_MAX_PATH];
        weaponModel[0] = '\0';

        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        float scale = 1.0;
        if (IsValidEntity(client))
        {
            scale = GetEntPropFloat(client, Prop_Send, "m_flModelScale");
        }

        // --- Find choreographed scene controlling player ---
        char sceneName[PLATFORM_MAX_PATH];
        strcopy(sceneName, sizeof(sceneName), g_sceneVcd[client]);
        
        int curSeq = GetEntProp(client, Prop_Send, "m_nSequence");

        char entry[1024];
        Format(entry, sizeof(entry),
            "%s{\"name\":\"%s\",\"team\":%d,\"x\":%.2f,\"y\":%.2f,\"z\":%.2f,\"pitch\":%.2f,\"yaw\":%.2f,\"roll\":%.2f,\"model\":\"%s\",\"skin\":%d,\"animation\":\"%s\",\"weapon_model\":\"%s\",\"scale\":%.2f,\"scene\":\"%s\",\"sequence\":%d}",
            first ? "" : ",",
            name2, GetClientTeam(client),
            pos[0], pos[1], pos[2],
            ang[0], ang[1], ang[2],
            model, skin, anim, "models/empty.mdl", scale, sceneName, curSeq
        );

        StrCat(json, sizeof(json), entry);
        first = false;
        playerCount++;
    }

    StrCat(json, sizeof(json), "]}");

    if (playerCount == 0)
    {
        return Plugin_Continue;
    }  
    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, SOCKET_URL);
    if (hRequest == INVALID_HANDLE)
        return Plugin_Continue;

    SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
    SteamWorks_SetHTTPRequestRawPostBody(hRequest, "application/json", json, strlen(json));
    SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPResponse);
    SteamWorks_SendHTTPRequest(hRequest);
    return Plugin_Continue;
}


public int OnHTTPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
{
    CloseHandle(hRequest);
    return 0;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "instanced_scripted_scene", false))
    {
    	SDKHook(entity, SDKHook_Spawn, OnSceneSpawned);
    }
}

stock bool:IsValidClient(iClient)
{
	if(iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return false;

	if(IsClientSourceTV(iClient) || IsClientReplay(iClient))
		return false;

	return true;
}

public Action OnSceneSpawned(int entity)
{
    int client = GetEntPropEnt(entity, Prop_Data, "m_hOwner");
    if (!IsValidClient(client)) return Plugin_Continue;

    char scenefile[128];
    GetEntPropString(entity, Prop_Data, "m_iszSceneFile", scenefile, sizeof(scenefile));
    strcopy(g_sceneVcd[client], sizeof(g_sceneVcd[client]), scenefile);

    // Clear it after 100 ms (0.1 seconds)
    CreateTimer(0.1, Timer_ClearScene, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}

// Called 100 ms later to clear the player's scene
public Action Timer_ClearScene(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
        return Plugin_Stop;

    strcopy(g_sceneVcd[client], sizeof(g_sceneVcd[client]), "\0");
    return Plugin_Stop;
}
