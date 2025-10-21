#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <steamworks>

#define SOCKET_URL "http://localhost:6003/update"
#define MAX_JSON_LEN 32768
#define MAX_SCENE_NAME 128
char g_sceneVcd[128][MAXPLAYERS + 1];

#define TRACE_URL "http://localhost:7001/traceattacks"
#define TRACE_URL2 "http://localhost:7000/traceattacks"

#define MAX_TRACES 128

// Emulate struct with parallel arrays
new gTraceAttacker[MAX_TRACES];
new gTraceVictim[MAX_TRACES];
new Float:gTraceDamage[MAX_TRACES]; 
new Float:gTraceHitPosX[MAX_TRACES];
new Float:gTraceHitPosY[MAX_TRACES];
new Float:gTraceHitPosZ[MAX_TRACES];    
#define CHAT_POST_URL "http://localhost:7000/chat"

new gTraceCount = 0;

Handle gH_GetWorldModel = null;

public void OnPluginStart()
{   
}

public void OnMapStart()
{
    PrintToServer("[Socket.IO] Position sync started"); 
    CreateTimer(0.1, Timer_SendAllPlayers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.1, TraceAttackGETTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
        if (!IsClientInGame(client) || !(GetClientTeam(client) == 2 || GetClientTeam(client) == 3))
            continue;

        float pos[3], ang[3];
        GetClientAbsOrigin(client, pos);
        GetClientAbsAngles(client, ang);

        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        float vel[3];
        GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

        char name2[MAX_NAME_LENGTH];
        Format(name2, sizeof(name2), "terror_%s", name);

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
                "%s{\"name\":\"%s\",\"team\":%d,\"x\":%.2f,\"y\":%.2f,\"z\":%.2f,\"pitch\":%.2f,\"yaw\":%.2f,\"roll\":%.2f,\"velx\":%.2f,\"vely\":%.2f,\"velz\":%.2f,\"model\":\"%s\",\"skin\":%d,\"animation\":\"%s\",\"weapon_model\":\"%s\",\"scale\":%.2f,\"scene\":\"%s\",\"sequence\":%d}",
                first ? "" : ",",
                name2, GetClientTeam(client),
                pos[0], pos[1], pos[2],
                ang[0], ang[1], ang[2],
                vel[0], vel[1], vel[2],
                model, skin, anim, "models/empty.mdl", scale, sceneName, curSeq
            );

        StrCat(json, sizeof(json), entry);
        first = false;
        playerCount++;
    }

    // --- Network "infected" and "witch" entities as well ---
    int maxEnts = GetMaxEntities();
    for (int ent = 0; ent <= maxEnts; ent++)
    {
        if (!IsValidEntity(ent))
            continue;

        char classname[64];
        GetEntityClassname(ent, classname, sizeof(classname));
        if (!StrEqual(classname, "infected") && !StrEqual(classname, "witch"))
            continue;

        float pos[3], ang[3], vel[3];
        GetEntPropVector(ent, Prop_Data, "m_vecOrigin", pos);
        GetEntPropVector(ent, Prop_Data, "m_angRotation", ang);

        char model[PLATFORM_MAX_PATH];
        GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));

        int skin = GetEntProp(ent, Prop_Send, "m_nSkin");
        int seq = GetEntProp(ent, Prop_Send, "m_nSequence");
        char anim[16];
        IntToString(seq, anim, sizeof(anim));

        float scale = GetEntPropFloat(ent, Prop_Send, "m_flModelScale");

        char entry[1024];
        Format(entry, sizeof(entry),
            "%s{\"name\":\"infected_%d\",\"team\":3,\"x\":%.2f,\"y\":%.2f,\"z\":%.2f,\"pitch\":%.2f,\"yaw\":%.2f,\"roll\":%.2f,\"velx\":%.2f,\"vely\":%.2f,\"velz\":%.2f,\"model\":\"%s\",\"skin\":%d,\"animation\":\"%s\",\"weapon_model\":\"%s\",\"scale\":%.2f,\"scene\":\"\",\"sequence\":%d}",
            first ? "" : ",",
            ent,
            pos[0], pos[1], pos[2],
            ang[0], ang[1], ang[2],
            0.0, 0.0, 0.0   ,
            "models/player/scout.mdl", skin, anim,
            "models/empty.mdl", scale, 0
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


// Hook TraceAttack

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    float vPos[3];
    GetClientEyePosition(victim, vPos);

    gTraceDamage[gTraceCount] = damage;
    gTraceHitPosX[gTraceCount] = vPos[0];
    gTraceHitPosY[gTraceCount] = vPos[1];
    gTraceHitPosZ[gTraceCount] = vPos[2]; 

    gTraceCount++;
    if (gTraceCount >= MAX_TRACES) gTraceCount = MAX_TRACES - 1; // prevent overflow
    return Plugin_Continue;
}

// --- Timer callback: POST all buffered traces as a JSON array ---
public Action TraceAttackPOSTTimer(Handle timer)
{
    if (gTraceCount == 0) return Plugin_Continue;

    // Build JSON array
    char json[8192];
    int pos = 0;
    pos += Format(json[pos], sizeof(json), "[");

    for (int i = 0; i < gTraceCount; i++)
    {
        char hitposStr[64];
        Format(hitposStr, sizeof(hitposStr), "%.6f %.6f %.6f", gTraceHitPosX[i], gTraceHitPosY[i], gTraceHitPosZ[i]);

        Format(json[pos], sizeof(json),
            "{\"hitpos\":\"%s\",\"damage\":%d}%s",gTraceDamage[i],
            hitposStr,
            (i == gTraceCount - 1) ? "" : ","
        );
    }

    pos += Format(json[pos], sizeof(json), "]");

    // Send HTTP POST
    Handle req = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, TRACE_URL);
    SteamWorks_SetHTTPRequestHeaderValue(req, "Content-Type", "application/json");
    SteamWorks_SetHTTPRequestRawPostBody(req, "application/json", json, strlen(json));
    SteamWorks_SendHTTPRequest(req);

    // Reset buffer
    gTraceCount = 0;

    return Plugin_Continue;
}
#define TRACE_RADIUS 20.0

public Action TraceAttackGETTimer(Handle timer)
{
    Handle req = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, TRACE_URL2);
    SteamWorks_SetHTTPCallbacks(req, OnTraceGetResponse);
    SteamWorks_SendHTTPRequest(req);
    return Plugin_Continue;
}

public int OnTraceGetResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
{
    char json[32768];

    int bodysize = 0;
    if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize) || bodysize <= 0)
    {
        //PrintToServer("[SYNC] Empty HTTP response or failed to read size (size=%d)", bodysize);
        return 0;
    }

    int maxBody = sizeof(json) - 1;
    if (bodysize > maxBody)
    {
        //PrintToServer("[SYNC] HTTP body size %d larger than buffer %d - truncating", bodysize, maxBody);
        bodysize = maxBody;
    }

    SteamWorks_GetHTTPResponseBodyData(hRequest, json, bodysize);
    json[bodysize] = '\0';

    int len = strlen(json);
    int pos = 0;

    // --- Find first object in array ---
    while (pos < len && json[pos] != '{') pos++;
    if (pos >= len) { CloseHandle(hRequest); return 0; }
    int objStart = pos;

    int objEnd = objStart;
    while (objEnd < len && json[objEnd] != '}') objEnd++;
    if (objEnd >= len) { CloseHandle(hRequest); return 0; }

    // --- Extract object substring ---
    char obj[1024];
    int objLen = objEnd - objStart + 1;
    if (objLen >= sizeof(obj)) objLen = sizeof(obj) - 1;
    for (int i = 0; i < objLen; i++) obj[i] = json[objStart + i];
    obj[objLen] = '\0';

    float hitpos[3] = {0.0, 0.0, 0.0};
    float damage = 30.0; // default

    // --- Parse "hitpos":"x y z" ---
    int keyPos = StrContains(obj, "\"hitpos\"", false);
    if (keyPos != -1)
    {
        keyPos += 7;
        while (obj[keyPos] && (obj[keyPos] == ' ' || obj[keyPos] == ':' || obj[keyPos] == '"')) keyPos++;

        char numStr[3][32];
        int numIndex = 0;
        int charIndex = 0;

        while (obj[keyPos] && obj[keyPos] != '"' && numIndex < 3)
        {
            char c = obj[keyPos];

            if ((c >= '0' && c <= '9') || c == '.' || c == '-' || c == 'e' || c == 'E')
                numStr[numIndex][charIndex++] = c;
            else if (c == ' ' || c == ',' || c == '\t')
            {
                if (charIndex > 0)
                {
                    numStr[numIndex][charIndex] = '\0';
                    hitpos[numIndex] = StringToFloat(numStr[numIndex]);
                    numIndex++;
                    charIndex = 0;
                }
            }
            keyPos++;
        }

        if (charIndex > 0 && numIndex < 3)
        {
            numStr[numIndex][charIndex] = '\0';
            hitpos[numIndex] = StringToFloat(numStr[numIndex]);
        }
    }

    // --- Parse "damage":<value> ---
    int keyPos2 = StrContains(obj, "\"damage\"", false);
    if (keyPos2 != -1)
    {
        keyPos2 += 7; // move past "damage"

        // Skip any non-digit characters until we find first digit
        while (obj[keyPos2] && (obj[keyPos2] < '0' || obj[keyPos2] > '9')) keyPos2++;

        char val[16]; int i = 0;
        while (obj[keyPos2] >= '0' && obj[keyPos2] <= '9') val[i++] = obj[keyPos2++];
        val[i] = '\0';
        damage = StringToFloat(val);
    }
    //PrintToServer("Parsed hitpos: %.2f, %.2f, %.2f | damage: %.2f", hitpos[0], hitpos[1], hitpos[2], damage);

    // --- Apply AoE damage (keep c, c, c) ---

    for (int ent = 1; ent <= GetMaxEntities(); ent++)
    {
        if (!IsValidEntity(ent))
            continue;

        // Ignore worldspawn and similar invalid types
        char classname[64];
        GetEntityClassname(ent, classname, sizeof(classname));
        if (StrEqual(classname, "worldspawn") || StrEqual(classname, "player_manager"))
            continue;

        float ePos[3];
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", ePos);

        float dist = GetVectorDistance(ePos, hitpos);
        if (dist <= TRACE_RADIUS)
        {
            // Optional: only damage entities that can actually take damage
            if (GetEntProp(ent, Prop_Data, "m_takedamage") != 0)
            {
                SDKHooks_TakeDamage(ent, ent, ent, damage, DMG_BULLET);
            }
        }
    }


    CloseHandle(hRequest);
    return 0;
}