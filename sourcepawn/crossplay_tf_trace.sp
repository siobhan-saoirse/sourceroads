/**
 * traceattacks.sp
 * Collects trace data on entity damage and periodically POSTs to a remote server.
 *
 * Requirements:
 *  - SDKHooks
 *  - SteamWorks
 */

#include <sourcemod>
#include <sdkhooks>
#include <steamworks>

#define MAX_TRACES 512
#define POST_INTERVAL 0.2
#define TRACE_URL "http://localhost:7000/traceattacks"

enum struct TraceData
{
    char hitpos[64];
    float damage;
    char attackerClass[64];
    char attackerSteam64[32];
}

TraceData g_TraceBuffer[MAX_TRACES];
int g_TraceCount = 0;

public void OnPluginStart()
{
    PrintToServer("[TraceAttacks] Plugin starting...");
    int maxEnts = GetMaxEntities();
    for (int i = 1; i < maxEnts; i++)
    {
        if (IsValidEntity(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }

    CreateTimer(POST_INTERVAL, Timer_FlushTraces, _, TIMER_REPEAT);
    RegAdminCmd("sm_cleartraces", Command_ClearTraces, ADMFLAG_ROOT);

    PrintToServer("[TraceAttacks] Initialization complete.");
}

public void OnEntityCreated(int entity, const char[] classname)
{
    int ent = entity;
    if (ent > 0 && ent < GetMaxEntities())
        SDKHook(ent, SDKHook_OnTakeDamage, OnTakeDamage);
}

stock bool:IsValidClient(iClient)
{
	if(iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return false;

	if(IsClientSourceTV(iClient) || IsClientReplay(iClient))
		return false;

	return true;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (damage <= 0.0 || !IsValidEntity(attacker))
        return Plugin_Continue;
    char cls[64];
    GetEntityClassname(attacker, cls, sizeof(cls));

    // Headcrab damage buff
    if (StrEqual(cls, "npc_headcrab_black", false) || StrEqual(cls, "npc_headcrab_poison", false))
        damage = 500.0;

    float pos[3];
    GetEntPropVector(victim, Prop_Send, "m_vecOrigin", pos);

    char hitpos[64];
    Format(hitpos, sizeof(hitpos), "%.6f %.6f %.6f", pos[0], pos[1], pos[2]);

    char steam64[32] = "N/A";
    if (IsClientInGame(attacker))
        GetClientAuthId(attacker, AuthId_SteamID64, steam64, sizeof(steam64));
    
    if (g_TraceCount < MAX_TRACES)
    {
        strcopy(g_TraceBuffer[g_TraceCount].hitpos, sizeof(g_TraceBuffer[g_TraceCount].hitpos), hitpos);
        g_TraceBuffer[g_TraceCount].damage = damage;
        strcopy(g_TraceBuffer[g_TraceCount].attackerClass, sizeof(g_TraceBuffer[g_TraceCount].attackerClass), cls);
        strcopy(g_TraceBuffer[g_TraceCount].attackerSteam64, sizeof(g_TraceBuffer[g_TraceCount].attackerSteam64), steam64);
        g_TraceCount++;
    }

    char classname[64];
    GetEntityClassname(victim, classname, sizeof(classname));
    if (StrContains(classname, "base_boss", false) != -1) {
        damage = -1.0;
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

// === Periodic POST ===
public Action Timer_FlushTraces(Handle timer)
{
    if (g_TraceCount == 0)
        return Plugin_Continue;

    int count = g_TraceCount;
    g_TraceCount = 0;

    char json[4096];
    json[0] = '\0';
    Format(json, sizeof(json), "[");

    for (int i = 0; i < count; i++)
    {
        char entry[256];
        Format(entry, sizeof(entry),
            "{\"hitpos\":\"%s\",\"damage\":%.1f,\"attackerClass\":\"%s\",\"attackerSteam64\":\"%s\"}%s",
            g_TraceBuffer[i].hitpos,
            g_TraceBuffer[i].damage,
            g_TraceBuffer[i].attackerClass,
            g_TraceBuffer[i].attackerSteam64,
            (i < count - 1) ? "," : "");

        StrCat(json, sizeof(json), entry);
    }

    StrCat(json, sizeof(json), "]");

    // POST via SteamWorks
    Handle req = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, TRACE_URL);
    if (req == null)
    {
        PrintToServer("[TraceAttack POST] Failed to create HTTP request.");
        g_TraceCount = count; // re-buffer
        return Plugin_Continue;
    }

    SteamWorks_SetHTTPRequestHeaderValue(req, "Content-Type", "application/json");
    SteamWorks_SetHTTPRequestRawPostBody(req, "application/json", json, strlen(json));
    SteamWorks_SetHTTPRequestNetworkActivityTimeout(req, 10);
    SteamWorks_SetHTTPCallbacks(req, HTTPCallback_OnPOSTComplete);
    SteamWorks_SendHTTPRequest(req);

    return Plugin_Continue;
}

public int HTTPCallback_OnPOSTComplete(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    if (bFailure || !bRequestSuccessful || eStatusCode < k_EHTTPStatusCode200OK || eStatusCode >= k_EHTTPStatusCode300MultipleChoices)
    {
        PrintToServer("[TraceAttack POST] HTTP failed or returned non-2xx status (%d)", eStatusCode);
        g_TraceCount = 0;
        return 0;
    }
    
    g_TraceCount = 0;
    return 0;
}

// === Admin command to clear ===
public Action Command_ClearTraces(int client, int args)
{
    g_TraceCount = 0;
    ReplyToCommand(client, "[TraceAttacks] Trace buffer cleared.");
    return Plugin_Handled;
}
