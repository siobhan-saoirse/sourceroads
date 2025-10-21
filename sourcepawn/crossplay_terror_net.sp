    #include <sourcemod>
    #include <sdktools>
    #include <steamworks>

    #define UPDATE_URL "http://localhost:2634/update_gmod"
    #define TF_UPDATE_URL "http://localhost:2634/update"
    #define TERROR_UPDATE_URL "http://localhost:2635/update_css"
    #define UPDATE_PROPS_URL "http://localhost:2634/update_props"
    #define UPDATE_SOUND_URL "http://localhost:2634/sound"
    #define SOUND_URL_1 "http://localhost:2639/sound"
    #define SOUND_URL_2 "http://localhost:2637/sound"
    #define SOUND_URL_3 "http://localhost:6004/sound"
    #define SOUND_URL_4 "http://localhost:6005/sound"
    #define SOUND_CHECK_INTERVAL 0.1
    #define UPDATE_INTERVAL 0.1
    #define INTERP_SPEED 50.0
    #define MAX_SPEED 300.0
    #define MAX_PLAYERS 4096
    #define MAX_PROPS 256
    #define MAX_NAME_LEN 64
    #define MAX_MODEL_LEN PLATFORM_MAX_PATH
    char g_szLastGlobalSound[PLATFORM_MAX_PATH];

    // --- Parallel arrays to store player data ---
    int gPlayerEnts[MAX_PLAYERS];
    float gPlayerPos[MAX_PLAYERS][3];
    char gPlayerNames[MAX_PLAYERS][MAX_NAME_LEN];
    char gPlayerModels[MAX_PLAYERS][MAX_MODEL_LEN];
    char gPlayerWeapons[MAX_PLAYERS][MAX_MODEL_LEN];
    int gWeaponProps[MAX_PLAYERS];
    bool activePlayers[MAX_PLAYERS];
    bool activeProps[MAX_PROPS];

    int gPlayerEnts2[MAX_PLAYERS];
    float gPlayerPos2[MAX_PLAYERS][3];
    char gPlayerNames2[MAX_PLAYERS][MAX_NAME_LEN];
    char gPlayerModels2[MAX_PLAYERS][MAX_MODEL_LEN];
    char gPlayerWeapons2[MAX_PLAYERS][MAX_MODEL_LEN];
    bool activePlayers2[MAX_PLAYERS];

    int gPlayerEnts3[MAX_PLAYERS];
    float gPlayerPos3[MAX_PLAYERS][3];
    char gPlayerNames3[MAX_PLAYERS][MAX_NAME_LEN];
    char gPlayerModels3[MAX_PLAYERS][MAX_MODEL_LEN];
    char gPlayerWeapons3[MAX_PLAYERS][MAX_MODEL_LEN];
    bool activePlayers3[MAX_PLAYERS];

    Handle g_SDKCallStudioFrameAdvance = null;

    // --- Prop storage (new) ---
    int gPropEnts[MAX_PROPS];
    char gPropIds[MAX_PROPS][32];              // unique id from JSON (string)
    char gPropModels[MAX_PROPS][MAX_MODEL_LEN];
    float gPropPos[MAX_PROPS][3];
    float gPropAngles[MAX_PROPS][3];
    float gPropScale[MAX_PROPS];
    // --- Global counters for unique targetnames ---
    static int gUniquePropCounter = 0;
    static int gUniqueNPCounter = 0;
    Handle g_hLookupPoseParameter;
    Handle g_hSetPoseParameter;

    // -------------------- Safe teleport queue --------------------
    #define MAX_PENDING_TELEPORTS 256
    int gPendingEntRef[MAX_PENDING_TELEPORTS];
    float gPendingPos[MAX_PENDING_TELEPORTS][3];
    float gPendingAng[MAX_PENDING_TELEPORTS][3];
    float gPendingVel[MAX_PENDING_TELEPORTS][3];
    bool gPendingUsed[MAX_PENDING_TELEPORTS];

    stock int _FindFreePendingSlot()
    {
        for (int i = 0; i < MAX_PENDING_TELEPORTS; i++)
        {
            if (!gPendingUsed[i])
                return i;
        }
        return -1;
    }

    /**
    * SafeTeleportSchedule
    *  - ent: entity index
    *  - pos/ang/vel: arrays. Pass NULL_VECTOR for unused vel
    *
    * Schedules the teleport to run next frame (CreateTimer 0.0)
    */
    stock void SafeTeleportSchedule(int ent, const float pos[3], const float ang[3], const float vel[3])
    {
        if (ent <= 0 || !IsValidEntity(ent))
            return;

        int slot = _FindFreePendingSlot();
        if (slot == -1)
        {
            // queue full; fall back to immediate but guarded attempt
            if (IsValidEntity(ent))
            {
                TeleportEntity(ent, pos, ang, vel);
            }
            return;
        }

        gPendingUsed[slot] = true;
        gPendingEntRef[slot] = EntIndexToEntRef(ent);

        // copy arrays defensively (if caller used stack arrays that might go out of scope)
            gPendingPos[slot][0] = pos[0];
            gPendingPos[slot][1] = pos[1];
            gPendingPos[slot][2] = pos[2];

            gPendingAng[slot][0] = ang[0];
            gPendingAng[slot][1] = ang[1];
            gPendingAng[slot][2] = ang[2];

            gPendingVel[slot][0] = vel[0];
            gPendingVel[slot][1] = vel[1];
            gPendingVel[slot][2] = vel[2];
        // Schedule to run next frame (0.0 sec). Pass the slot index in the 'any' param.
        DoTeleport(slot);
    }

    public Action DoTeleport(any:data)
    {
        int slot = data;
        if (slot < 0 || slot >= MAX_PENDING_TELEPORTS)
            return Plugin_Stop;

        if (!gPendingUsed[slot])
            return Plugin_Stop;

        int entRef = gPendingEntRef[slot];
        int ent = EntRefToEntIndex(entRef);

        // Validate and do the teleport
        if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
        {
            float pos[3];
            float ang[3];
            float vel[3];

            pos[0] = gPendingPos[slot][0];
            pos[1] = gPendingPos[slot][1];
            pos[2] = gPendingPos[slot][2];

            ang[0] = gPendingAng[slot][0];
            ang[1] = gPendingAng[slot][1];
            ang[2] = gPendingAng[slot][2];

            vel[0] = gPendingVel[slot][0];
            vel[1] = gPendingVel[slot][1];
            vel[2] = gPendingVel[slot][2];

            // Bounds sanity check (avoid NaN/Inf/huge values)
            if (pos[0] > -100000000 && pos[0] < 100000000 &&
                pos[1] > -100000000 && pos[1] < 100000000 &&
                pos[2] > -100000000 && pos[2] < 100000000 &&
                ang[0] > -100000000 && ang[0] < 100000000 &&
                ang[1] > -100000000 && ang[1] < 100000000 &&
                ang[2] > -100000000 && ang[2] < 100000000)
            {
                // Best-effort clear parent (commented by default; enable if you need it)
                // AcceptEntityInput(ent, "ClearParent");

                TeleportEntity(ent, pos, ang, vel);
            }
        }

        // clear slot
        gPendingUsed[slot] = false;
        gPendingEntRef[slot] = 0;
        return Plugin_Stop;
    }

    // --- Helper functions ---
    int FindPlayerIndex(const char[] name)
    {
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            int ent = gPlayerEnts[i];
            if (ent != 0 && StrEqual(gPlayerNames[i], name) && IsValidEntity(ent))
            {
                char classname[64];
                GetEntityClassname(ent, classname, sizeof(classname));
                if (StrContains(classname,"prop_dynamic_override",false))
                    return i; // found
            }
            ent = gPlayerEnts2[i];
            if (ent != 0 && StrEqual(gPlayerNames2[i], name) && IsValidEntity(ent))
            {
                char classname[64];
                GetEntityClassname(ent, classname, sizeof(classname));
                if (StrContains(classname,"prop_dynamic_override",false))
                    return i; // found
            }
        }
        return -1;
    }

    int FindPlayerIndexTF(const char[] name)
    {
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            int ent = gPlayerEnts2[i];
            if (ent != 0 && StrEqual(gPlayerNames2[i], name) && IsValidEntity(ent))
            {
                char classname[64];
                GetEntityClassname(ent, classname, sizeof(classname));
                if (StrContains(classname,"prop_dynamic_override",false))
                    return i; // found
            }
        }
        return -1;
    }

    int FindPlayerIndexTERROR(const char[] name)
    {
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            int ent = gPlayerEnts3[i];
            if (ent != 0 && StrEqual(gPlayerNames3[i], name) && IsValidEntity(ent))
            {
                char classname[64];
                GetEntityClassname(ent, classname, sizeof(classname));
                if (StrContains(classname,"prop_dynamic_override",false))
                    return i; // found
            }
        }
        return -1;
    }


    int FindFreeSlot()
    {
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            if (gPlayerEnts[i] == 0)
                return i;
        }
        return -1;
    }

    int FindFreeSlotTF()
    {
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            if (gPlayerEnts2[i] == 0)
                return i;
        }
        return -1;
    }

    int FindFreeSlotTERROR()
    {
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            if (gPlayerEnts3[i] == 0)
                return i;
        }
        return -1;
    }

    int FindPropIndexById(const char[] id)
    {
        for (int i = 0; i < MAX_PROPS; i++)
        {   
            if (gPropEnts[i] != 0 && StrEqual(gPropIds[i], id))
                return i;
        }
        return -1;
    }

    int FindFreePropSlot()
    {
        for (int i = 0; i < MAX_PROPS; i++)
        {
            if (gPropEnts[i] == 0)
                return i;
        }
        return -1;
    }

    // ### ADDED: helper to find an entity by its targetname (returns 0 if none)
    int FindEntityByTargetName(const char[] target)
    {
        if (target[0] == '\0') return 0;
        int ent = FindEntityByName(target);
        if (ent <= 0) return 0;
        if (!IsValidEntity(ent)) return 0;
        return ent;
    }
    int FindEntityByName(const char[] targetname)
    {
        char entName[128];
        int maxEnts = GetMaxEntities();

        for (int ent = MaxClients + 1; ent <= maxEnts; ent++)
        {
            if (!IsValidEntity(ent))
                continue;

            GetEntPropString(ent, Prop_Data, "m_iName", entName, sizeof(entName));

            if (StrEqual(entName, targetname, false))
            {
                return ent;
            }
        }

        return -1; // Not found
    }


    bool ExtractJSONString(const char[] json, const char[] key, char[] out, int maxlen)
    {
        char pattern[128];
        Format(pattern, sizeof(pattern), "\"%s\":\"", key);

        int start = StrContains(json, pattern, false);
        if (start == -1) return false;

        start += strlen(pattern);
        int end = start;
        while (json[end] != '"' && json[end] != '\0') end++;

        int len = end - start;
        if (len >= maxlen) len = maxlen - 1;

        int i;
        for (i = 0; i < len; i++)
        {
            out[i] = json[start + i];
        }
        out[i] = '\0';
        return true;
    }

    float ExtractJSONFloat(const char[] json, const char[] key)
    {
        char pattern[128], buffer[64];

        Format(pattern, sizeof(pattern), "\"%s\":", key);

        int start = StrContains(json, pattern, false);
        if (start == -1) return 0.0;

        start += strlen(pattern);
        int end = start;

        // find end of number
        while ((json[end] >= '0' && json[end] <= '9') || json[end]=='.' || json[end]=='-') end++;

        int len = end - start;
        if (len >= sizeof(buffer)) len = sizeof(buffer) - 1;

        int i;
        for (i = 0; i < len; i++)
        {
            buffer[i] = json[start + i];
        }
        buffer[i] = '\0';

        return StringToFloat(buffer);
    }

    int ExtractJSONInt(const char[] json, const char[] key)
    {
        return RoundToNearest(ExtractJSONFloat(json, key));
    }

    // --- Plugin lifecycle ---
    public void OnPluginStart()
    {
        // leave empty 4 now
        AddNormalSoundHook(CritWeaponSH);
    }

    // --- Plugin start ---
    public void OnMapStart()
    {
        PrecacheModel("models/survivors/survivor_gambler.mdl");
        PrecacheModel("models/survivors/survivor_coach.mdl"); 
        PrecacheModel("models/survivors/survivor_namvet.mdl"); 
        CreateTimer(UPDATE_INTERVAL, Timer_SendUpdates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(UPDATE_INTERVAL, Timer_SendUpdatesTF, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(UPDATE_INTERVAL, Timer_SendUpdatesTERROR, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(0.1, Timer_CheckSounds, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        PrintToServer("[Socket.IO] Position sync started (interval: %.2f sec)", UPDATE_INTERVAL);
    }

    // --- Timer to fetch updates (players + props) ---
    public Action Timer_SendUpdates(Handle timer)
    {
        // Player update request
        Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, UPDATE_URL);
        if (hRequest != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPResponse);
            SteamWorks_SendHTTPRequest(hRequest);
        }

        // Props update request (separate callback)
        Handle hPropReq = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, UPDATE_PROPS_URL);
        if (hPropReq != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hPropReq, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hPropReq, OnHTTPPropsResponse);
            SteamWorks_SendHTTPRequest(hPropReq);
        }

        return Plugin_Continue;
    }
    public Action Timer_SendUpdatesTF(Handle timer)
    {
        // Player update request
        Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, TF_UPDATE_URL);
        if (hRequest != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPResponse2);
            SteamWorks_SendHTTPRequest(hRequest);
        }

        return Plugin_Continue;
    }
    public Action Timer_SendUpdatesTERROR(Handle timer)
    {
        // Player update request
        Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, TERROR_UPDATE_URL);
        if (hRequest != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPResponse3);
            SteamWorks_SendHTTPRequest(hRequest);
        }

        return Plugin_Continue;
    }

    // --- Player HTTP response (unchanged logic, hardened, with reuse changes) ---
    public int OnHTTPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
    {
        if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
        {
            PrintToServer("[SYNC] HTTP request failed or returned non-200: failure=%d success=%d code=%d", bFailure, bRequestSuccessful, eStatusCode);
            return 0;
        }

        int bodysize = 0;
        if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize) || bodysize <= 0)
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
        SteamWorks_GetHTTPResponseBodyData(hRequest, body, bodysize);
        body[bodysize] = '\0';

        if (strlen(body) == 0)
        {
            PrintToServer("[SYNC] HTTP body read but empty string");
            return 0;
        }

        int bodyLen = strlen(body);
        int pos = 0;

        while (pos < bodyLen)
        {
            // find next '{'
            int objStart = -1;
            for (int i = pos; i < bodyLen; i++)
            {
                if (body[i] == '{') { objStart = i; break; }
            }
            if (objStart == -1) break;

            // find matching '}' after objStart
            int objEnd = -1;
            for (int i = objStart + 1; i < bodyLen; i++)
            {
                if (body[i] == '}') { objEnd = i; break; }
            }
            if (objEnd == -1) break;

            // copy the object substring safely
            int len = objEnd - objStart + 1;
            if (len > 1023) len = 1023;
            char entry[1024];
            for (int i = 0; i < len; i++) entry[i] = body[objStart + i];
            entry[len] = '\0';

            pos = objEnd + 1; // advance

            // --- Extract fields safely (best-effort simple parsing) ---
            char name[MAX_NAME_LEN]; name[0] = '\0';
            char model[MAX_MODEL_LEN]; model[0] = '\0';
            char weaponModel[MAX_MODEL_LEN]; weaponModel[0] = '\0';
            float x = 0.0, y = 0.0, z = 0.0;
            float pitch = 0.0, yaw = 0.0, roll = 0.0;
            int skin = 0, animation = 0;
            float modelscale = 1.0;

            if (!ExtractJSONString(entry, "name", name, sizeof(name)))
            {
                PrintToServer("[SYNC] Skipping entry: missing name");
                continue;
            }

            ExtractJSONString(entry, "model", model, sizeof(model));
            ExtractJSONString(entry, "weapon_model", weaponModel, sizeof(weaponModel));

            x = ExtractJSONFloat(entry, "x");
            y = ExtractJSONFloat(entry, "y");
            z = ExtractJSONFloat(entry, "z");
            pitch = ExtractJSONFloat(entry, "pitch");
            yaw = ExtractJSONFloat(entry, "yaw");
            roll = ExtractJSONFloat(entry, "roll");
            skin = ExtractJSONInt(entry, "skin");
            animation = ExtractJSONInt(entry, "animation");

            // optional scale key (key name "scale" used by GMod; accept both)
            float maybeScale = ExtractJSONFloat(entry, "scale");
            if (maybeScale > 0.0) modelscale = maybeScale;
            else
            {
                maybeScale = ExtractJSONFloat(entry, "modelScale");
                if (maybeScale > 0.0) modelscale = maybeScale;
            }

            // Find existing slot
            int idx = FindPlayerIndex(name);
            if (idx == -1)
            {
                idx = FindFreeSlot();
                if (idx == -1)
                {
                    continue;
                }

                // ### CHANGED: try to reuse an existing entity by targetname (player name)
                
            // ### CHANGED: try to find an existing prop_dynamic_override for this player
            int ent = 0;
            int maxEdicts = GetMaxEntities();

            for (int i = 1; i <= maxEdicts; i++) // start from 1; 0 is world
            {
                if (!IsValidEntity(i)) continue;

                char classname[64];
                GetEntityClassname(i, classname, sizeof(classname));

                if (StrEqual(classname, "prop_dynamic_override"))
                {
                    char existingName[64];
                    GetEntPropString(i, Prop_Data, "m_iName", existingName, sizeof(existingName));

                    if (StrContains(existingName, "gmod_") != -1 && StrContains(existingName, name) != -1)
                    {
                        ent = i;
                        break; // Found an existing entity for this player
                    }
                }
            }

            if (ent == 0)
            {
                // No existing entity, create a new one
                ent = CreateEntityByName("prop_dynamic_override");
                if (ent <= 0)
                {
                    PrintToServer("[SYNC] CreateEntityByName failed for '%s' (ent=%d)", name, ent);
                    continue;
                }

                char npcTargetName[64];
                Format(npcTargetName, sizeof(npcTargetName), "gmod_%s_%d", name, gUniqueNPCounter++);
                // Assign a unique targetname so we can find/reuse it later
                DispatchKeyValue(ent, "targetname", npcTargetName); 
                DispatchKeyValue(ent, "health", "9999999");

                    // Use kleiner as default until model provided
                    SetEntityModel(ent, "models/survivors/survivor_namvet.mdl");
                }

                // set solid type & clientside animation (only once; avoid repeating to reduce flicker)
                SetEntProp(ent, Prop_Send, "m_nSolidType", 2);
                SetEntProp(ent, Prop_Data, "m_nSolidType", 2);
                SetEntProp(ent, Prop_Send, "m_bClientSideAnimation", true);

                float tpos[3]; tpos[0] = x; tpos[1] = y; tpos[2] = z;
                float tang[3]; tang[0] = pitch; tang[1] = yaw; tang[2] = roll;
                SafeTeleportSchedule(ent, tpos, tang, NULL_VECTOR);

                // set scale if available
                if (modelscale > 0.0)
                {
                    SetEntPropFloat(ent, Prop_Send, "m_flModelScale", modelscale);
                }

                strcopy(gPlayerNames[idx], sizeof(gPlayerNames[idx]), name);
                strcopy(gPlayerModels[idx], sizeof(gPlayerModels[idx]), model);
                strcopy(gPlayerWeapons[idx], sizeof(gPlayerWeapons[idx]), weaponModel);
                gPlayerPos[idx][0] = x; gPlayerPos[idx][1] = y; gPlayerPos[idx][2] = z;

                gPlayerEnts[idx] = ent;
                activePlayers[idx] = true;
            }
            else
            {
                int ent = gPlayerEnts[idx];
                char classname[64];
                if (IsValidEntity(ent)) {
                    GetEntityClassname(ent, classname, sizeof(classname));

                    if (!IsValidEntity(ent) || IsValidEntity(ent) && !StrContains(classname, "prop_dynamic_override", false))
                    {
                        gPlayerEnts[idx] = 0;
                        continue;
                    }

                    float dt = UPDATE_INTERVAL;
                    float newPos[3];
                    newPos[0] = gPlayerPos[idx][0] + (x - gPlayerPos[idx][0]) * INTERP_SPEED * dt;
                    newPos[1] = gPlayerPos[idx][1] + (y - gPlayerPos[idx][1]) * INTERP_SPEED * dt;
                    newPos[2] = gPlayerPos[idx][2] + (z - gPlayerPos[idx][2]) * INTERP_SPEED * dt;
                    float angles[3]; angles[0] = pitch; angles[1] = yaw; angles[2] = roll;

                    SafeTeleportSchedule(ent, newPos, angles, NULL_VECTOR);

                    // update stored pos to target (not interpolated) so next interpolation is correct
                    gPlayerPos[idx][0] = x; gPlayerPos[idx][1] = y; gPlayerPos[idx][2] = z;

                    // apply model scale if requested
                    if (modelscale > 0.0)
                    {
                        SetEntPropFloat(ent, Prop_Send, "m_flModelScale", modelscale);
                    }

                    activePlayers[idx] = true;
                }
            }
        } // end while parsing objects

        // cleanup player slots 
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            if (gPlayerEnts[i] != 0 && !activePlayers[i])
            {
                if (IsValidEntity(gPlayerEnts[i]))
                {
                    AcceptEntityInput(gPlayerEnts[i], "Kill");
                }
                gPlayerEnts[i] = 0;
            }

            if (gWeaponProps[i] != 0 && !activePlayers[i])
            {
                if (IsValidEntity(gWeaponProps[i]))
                {
                    AcceptEntityInput(gWeaponProps[i], "Kill");
                }
                gWeaponProps[i] = 0;
            }
        }

        if (hRequest != INVALID_HANDLE) CloseHandle(hRequest);

        return 0;
    }

    public int OnHTTPResponse2(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
    {
        if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
        {
            PrintToServer("[SYNC] HTTP request failed or returned non-200: failure=%d success=%d code=%d", bFailure, bRequestSuccessful, eStatusCode);
            return 0;
        }

        int bodysize = 0;
        if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize) || bodysize <= 0)
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
        SteamWorks_GetHTTPResponseBodyData(hRequest, body, bodysize);
        body[bodysize] = '\0';

        if (strlen(body) == 0)
        {
            PrintToServer("[SYNC] HTTP body read but empty string");
            return 0;
        }

        int bodyLen = strlen(body);
        int pos = 0;

        while (pos < bodyLen)
        {
            // find next '{'
            int objStart = -1;
            for (int i = pos; i < bodyLen; i++)
            {
                if (body[i] == '{') { objStart = i; break; }
            }
            if (objStart == -1) break;

            // find matching '}' after objStart
            int objEnd = -1;
            for (int i = objStart + 1; i < bodyLen; i++)
            {
                if (body[i] == '}') { objEnd = i; break; }
            }
            if (objEnd == -1) break;

            // copy the object substring safely
            int len = objEnd - objStart + 1;
            if (len > 1023) len = 1023;
            char entry[1024];
            for (int i = 0; i < len; i++) entry[i] = body[objStart + i];
            entry[len] = '\0';

            pos = objEnd + 1; // advance

            // --- Extract fields safely (best-effort simple parsing) ---
            char name[MAX_NAME_LEN]; name[0] = '\0';
            char model[MAX_MODEL_LEN]; model[0] = '\0';
            char weaponModel[MAX_MODEL_LEN]; weaponModel[0] = '\0';
            float x = 0.0, y = 0.0, z = 0.0;
            float pitch = 0.0, yaw = 0.0, roll = 0.0;
            int skin = 0, animation = 0;
            float modelscale = 1.0;

            if (!ExtractJSONString(entry, "name", name, sizeof(name)))
            {
                PrintToServer("[SYNC] Skipping entry: missing name");
                continue;
            }

            ExtractJSONString(entry, "model", model, sizeof(model));
            ExtractJSONString(entry, "weapon_model", weaponModel, sizeof(weaponModel));

            x = ExtractJSONFloat(entry, "x");
            y = ExtractJSONFloat(entry, "y");
            z = ExtractJSONFloat(entry, "z");
            pitch = ExtractJSONFloat(entry, "pitch");
            yaw = ExtractJSONFloat(entry, "yaw");
            roll = ExtractJSONFloat(entry, "roll");
            skin = ExtractJSONInt(entry, "skin");
            animation = ExtractJSONInt(entry, "animation");

            // optional scale key (key name "scale" used by GMod; accept both)
            float maybeScale = ExtractJSONFloat(entry, "scale");
            if (maybeScale > 0.0) modelscale = maybeScale;
            else
            {
                maybeScale = ExtractJSONFloat(entry, "modelScale");
                if (maybeScale > 0.0) modelscale = maybeScale;
            }

            // Find existing slot
            int idx = FindPlayerIndexTF(name);
            if (idx == -1)
            {
                idx = FindFreeSlotTF();
                if (idx == -1)
                {
                    continue;
                }
    
                // ### CHANGED: try to find an existing prop_dynamic_override for this player
                int ent = 0;
                int maxEdicts = GetMaxEntities();

                for (int i = 1; i <= maxEdicts; i++) // start from 1; 0 is world
                {
                    if (!IsValidEntity(i)) continue;

                    char classname[64];
                    GetEntityClassname(i, classname, sizeof(classname));

                    if (StrEqual(classname, "prop_dynamic_override"))
                    {
                        char existingName[64];
                        GetEntPropString(i, Prop_Data, "m_iName", existingName, sizeof(existingName));

                        if (StrContains(existingName, "tf_") != -1 && StrContains(existingName, name) != -1)
                        {
                            ent = i;
                            break; // Found an existing entity for this player
                        }
                    }
                }

                if (ent == 0)
                {
                    // No existing entity, create a new one
                    ent = CreateEntityByName("prop_dynamic_override");
                    if (ent <= 0)
                    {
                        PrintToServer("[SYNC] CreateEntityByName failed for '%s' (ent=%d)", name, ent);
                        continue;
                    }

                    char npcTargetName[64];
                    Format(npcTargetName, sizeof(npcTargetName), "tf_%s_%d", name, gUniqueNPCounter++);
                    // Assign a unique targetname so we can find/reuse it later
                    DispatchKeyValue(ent, "targetname", npcTargetName); 
                    DispatchKeyValue(ent, "health", "9999999");

                    // Use kleiner as default until model provided
                    SetEntityModel(ent, "models/survivors/survivor_coach.mdl");
                }

                // set solid type & clientside animation (only once; avoid repeating to reduce flicker)
                SetEntProp(ent, Prop_Send, "m_nSolidType", 2);
                SetEntProp(ent, Prop_Data, "m_nSolidType", 2);
                SetEntProp(ent, Prop_Send, "m_bClientSideAnimation", true);

                float tpos[3]; tpos[0] = x; tpos[1] = y; tpos[2] = z;
                float tang[3]; tang[0] = pitch; tang[1] = yaw; tang[2] = roll;
                SafeTeleportSchedule(ent, tpos, tang, NULL_VECTOR);

                // set scale if available
                if (modelscale > 0.0)
                {
                    SetEntPropFloat(ent, Prop_Send, "m_flModelScale", modelscale);
                }

                strcopy(gPlayerNames2[idx], sizeof(gPlayerNames2[idx]), name);
                strcopy(gPlayerModels2[idx], sizeof(gPlayerModels2[idx]), model);
                strcopy(gPlayerWeapons2[idx], sizeof(gPlayerWeapons2[idx]), weaponModel);
                gPlayerPos2[idx][0] = x; gPlayerPos2[idx][1] = y; gPlayerPos2[idx][2] = z;

                gPlayerEnts2[idx] = ent;
                activePlayers2[idx] = true;
            }
            else
            {
                int ent = gPlayerEnts2[idx];
                char classname[64];
                if (IsValidEntity(ent)) {
                    GetEntityClassname(ent, classname, sizeof(classname));

                    if (!IsValidEntity(ent) || IsValidEntity(ent) && !StrContains(classname, "prop_dynamic_override", false))
                    {
                        gPlayerEnts2[idx] = 0;
                        continue;
                    }

                    float dt = UPDATE_INTERVAL;
                    float newPos[3];
                    newPos[0] = gPlayerPos2[idx][0] + (x - gPlayerPos2[idx][0]) * INTERP_SPEED * dt;
                    newPos[1] = gPlayerPos2[idx][1] + (y - gPlayerPos2[idx][1]) * INTERP_SPEED * dt;
                    newPos[2] = gPlayerPos2[idx][2] + (z - gPlayerPos2[idx][2]) * INTERP_SPEED * dt;
                    float angles[3]; angles[0] = pitch; angles[1] = yaw; angles[2] = roll;

                    SafeTeleportSchedule(ent, newPos, angles, NULL_VECTOR);

                    // update stored pos to target (not interpolated) so next interpolation is correct
                    gPlayerPos2[idx][0] = x; gPlayerPos2[idx][1] = y; gPlayerPos2[idx][2] = z;

                    // apply model scale if requested
                    if (modelscale > 0.0)
                    {
                        SetEntPropFloat(ent, Prop_Send, "m_flModelScale", modelscale);
                    }

                    activePlayers2[idx] = true;
                }
            }
        } // end while parsing objects

        // cleanup player slots 
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            if (gPlayerEnts2[i] != 0 && !activePlayers2[i])
            {
                if (IsValidEntity(gPlayerEnts2[i]))
                {
                    AcceptEntityInput(gPlayerEnts2[i], "Kill");
                }
                gPlayerEnts2[i] = 0;
            }
        }

        if (hRequest != INVALID_HANDLE) CloseHandle(hRequest);

        return 0;
    }

    public int OnHTTPPropsResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
    {
        if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
        {
            PrintToServer("[PROPS] HTTP request failed or returned non-200: failure=%d success=%d code=%d", bFailure, bRequestSuccessful, eStatusCode);
            return 0;
        }

        int bodysize = 0;
        if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize) || bodysize <= 0)
        {
            PrintToServer("[PROPS] Empty HTTP response or failed to read size (size=%d)", bodysize);
            return 0;
        }

        char propsJson[8192];
        int maxBody = sizeof(propsJson) - 1;
        if (bodysize > maxBody) bodysize = maxBody;

        SteamWorks_GetHTTPResponseBodyData(hRequest, propsJson, bodysize);
        propsJson[bodysize] = '\0';

        if (strlen(propsJson) == 0)
            return 0;

        // Mark all props inactive initially
        for (int i = 0; i < MAX_PROPS; i++)
            activeProps[i] = false;

        int start = 0;
        int propsLen = strlen(propsJson);

        while (start < propsLen)
        {
            // Find next object boundaries '{' ... '}'
            int objStart = -1;
            int objEnd = -1;

            // Find '{'
            for (int i = start; i < propsLen; i++)
            {
                if (propsJson[i] == '{') { objStart = i; break; }
            }
            if (objStart == -1) break;

            // Find matching '}'
            for (int i = objStart + 1; i < propsLen; i++)
            {
                if (propsJson[i] == '}') { objEnd = i; break; }
            }
            if (objEnd == -1) break;

            // Copy substring into entry buffer
            int entryLen = objEnd - objStart + 1;
            if (entryLen >= 1024) entryLen = 1023;

            char entry[1024];
            for (int i = 0; i < entryLen; i++)
            {
                entry[i] = propsJson[objStart + i];
            }
            entry[entryLen] = '\0';

            start = objEnd + 1; // advance start for next object

            // --- Extract fields ---
            char id[MAX_NAME_LEN]; id[0] = '\0';
            char model[MAX_MODEL_LEN]; model[0] = '\0';
            float x = 0.0, y = 0.0, z = 0.0;
            float pitch = 0.0, yaw = 0.0, roll = 0.0;
            float scale = 1.0;
            int skin = 0;
            int sequence = 0;
            float cycle = 0.0;

            if (!ExtractJSONString(entry, "id", id, sizeof(id)))
            {
                continue;
            }

            ExtractJSONString(entry, "model", model, sizeof(model));
            if (!IsModelPrecached(model)) {
                PrecacheModel(model);
            }

            x = ExtractJSONFloat(entry, "x");
            y = ExtractJSONFloat(entry, "y");
            z = ExtractJSONFloat(entry, "z");
            pitch = ExtractJSONFloat(entry, "pitch");
            yaw = ExtractJSONFloat(entry, "yaw");
            roll = ExtractJSONFloat(entry, "roll");
            scale = ExtractJSONFloat(entry, "modelScale");
            if (scale <= 0.0) scale = ExtractJSONFloat(entry, "scale");
            skin = ExtractJSONInt(entry, "skin");
            sequence = ExtractJSONInt(entry, "sequence");
            cycle = ExtractJSONFloat(entry, "cycle");

            // --- Find or create prop slot ---
            int pidx = FindPropIndexById(id);
            if (pidx == -1)
            {
                pidx = FindFreePropSlot();
                if (pidx == -1)
                {
                    continue;
                }

                int pent = FindEntityByTargetName(id);
                if (pent != 0 && !IsValidEntity(pent)) pent = 0;

                if (pent == 0)
                {
                    pent = CreateEntityByName("prop_dynamic_override");
                    if (pent <= 0)
                    {
                        PrintToServer("[PROPS] CreateEntityByName failed for '%s'", id);
                        continue;
                    }

                    char propTarget[64];
                    Format(propTarget, sizeof(propTarget), "%s_%d", id, gUniquePropCounter++);
                    DispatchKeyValue(pent, "targetname", propTarget);
                    DispatchKeyValue(pent, "health", "9999999");

                    if (model[0] != '\0')
                        SetEntityModel(pent, model);

                    SetEntProp(pent, Prop_Send, "m_nSolidType", 2);
                    SetEntProp(pent, Prop_Data, "m_nSolidType", 2);
                    SetEntProp(pent, Prop_Send, "m_bClientSideAnimation", true);
                }

                float pos[3]/* = {x, y, z}; */
                pos[0] = x;
                pos[1] = y;
                pos[2] = z;
                float ang[3]/* = {pitch, yaw, roll};*/
                ang[0] = pitch;
                ang[1] = yaw;
                ang[2] = roll;
                SafeTeleportSchedule(pent, pos, ang, NULL_VECTOR);

                if (scale > 0.0)
                    SetEntPropFloat(pent, Prop_Send, "m_flModelScale", scale);
                if (skin != 0)
                    SetEntProp(pent, Prop_Send, "m_nSkin", skin);

                gPropEnts[pidx] = pent;
                strcopy(gPropIds[pidx], sizeof(gPropIds[pidx]), id);
                strcopy(gPropModels[pidx], sizeof(gPropModels[pidx]), model);
                gPropPos[pidx][0] = x; gPropPos[pidx][1] = y; gPropPos[pidx][2] = z;
                gPropAngles[pidx][0] = pitch; gPropAngles[pidx][1] = yaw; gPropAngles[pidx][2] = roll;
                gPropScale[pidx] = scale;
                activeProps[pidx] = true;
            }
            else
            {
                int pent = gPropEnts[pidx];
                if (!IsValidEntity(pent))
                {
                    gPropEnts[pidx] = 0;
                    continue;
                }

                float pos[3]/* = {x, y, z}; */
                pos[0] = x;
                pos[1] = y;
                pos[2] = z;
                float ang[3]/* = {pitch, yaw, roll};*/
                ang[0] = pitch;
                ang[1] = yaw;
                ang[2] = roll;
                SafeTeleportSchedule(pent, pos, ang, NULL_VECTOR);

                if (sequence > 0)
                {
                    int curSeq = GetEntProp(pent, Prop_Send, "m_nSequence");
                    if (curSeq != sequence)
                    {
                        SetEntProp(pent, Prop_Send, "m_nSequence", sequence);
                        SetEntPropFloat(pent, Prop_Send, "m_flPlaybackRate", 1.0);

                        SetEntPropFloat(pent, Prop_Send, "m_flCycle", 0.0);
                    }
                }

                if (scale > 0.0 && scale != gPropScale[pidx])
                {
                    SetEntPropFloat(pent, Prop_Send, "m_flModelScale", scale);
                    gPropScale[pidx] = scale;
                }

                gPropPos[pidx][0] = x; gPropPos[pidx][1] = y; gPropPos[pidx][2] = z;
                gPropAngles[pidx][0] = pitch; gPropAngles[pidx][1] = yaw; gPropAngles[pidx][2] = roll;
                activeProps[pidx] = true;
            }
        }

        // --- Cleanup unused props ---
        for (int i = 0; i < MAX_PROPS; i++)
        {
            if (gPropEnts[i] != 0 && !activeProps[i])
            {
                if (IsValidEntity(gPropEnts[i]))
                    AcceptEntityInput(gPropEnts[i], "Kill");

                gPropEnts[i] = 0;
                gPropIds[i][0] = '\0';
                gPropModels[i][0] = '\0';
                gPropScale[i] = 0.0;
            }
        }

        if (hRequest != INVALID_HANDLE) CloseHandle(hRequest);

        return 0;
    }

    // --- Timer to fetch sound events ---
    public Action Timer_CheckSounds(Handle timer)
    {
        Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, UPDATE_SOUND_URL);
        if (hRequest != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPSoundResponse);
            SteamWorks_SendHTTPRequest(hRequest);
        }
        hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, SOUND_URL_2);
        if (hRequest != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPSoundResponse);
            SteamWorks_SendHTTPRequest(hRequest);
        }
        hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, SOUND_URL_3);
        if (hRequest != INVALID_HANDLE)
        {
            SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
            SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPSoundResponse);
            SteamWorks_SendHTTPRequest(hRequest);
        }
        return Plugin_Continue;
    }

    public int OnHTTPSoundResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
    {
        if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
            return 0;

        int bodysize = 0;
        if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize) || bodysize <= 0)
            return 0;

        char body[8192];
        if (bodysize > sizeof(body) - 1)
            bodysize = sizeof(body) - 1;

        SteamWorks_GetHTTPResponseBodyData(hRequest, body, bodysize);
        body[bodysize] = '\0';

        if (strlen(body) == 0)
            return 0;

        int start = 0;
        int bodyLen = strlen(body);

        // --- Each sound entry is a JSON object {...} ---
        while (start < bodyLen)
        {
            int objStart = -1;
            int objEnd = -1;

            // Find '{'
            for (int i = start; i < bodyLen; i++)
            {
                if (body[i] == '{') { objStart = i; break; }
            }
            if (objStart == -1)
                break;

            // Find '}'
            for (int i = objStart + 1; i < bodyLen; i++)
            {
                if (body[i] == '}') { objEnd = i; break; }
            }
            if (objEnd == -1)
                break;

            int entryLen = objEnd - objStart + 1;
            if (entryLen >= 1024) entryLen = 1023;

            char entry[1024];
            for (int i = 0; i < entryLen; i++)
                entry[i] = body[objStart + i];
            entry[entryLen] = '\0';

            start = objEnd + 1;

            // --- Extract fields from JSON object ---
            char sound[256]; sound[0] = '\0';
            char name[64]; name[0] = '\0';
            char className[64]; className[0] = '\0';
            char model[128]; model[0] = '\0';
            char posString[128]; posString[0] = '\0';

            float pos[3];
            float volume = 1.0; 
            int pitch = 100;
            int level = 75;
            float x = 0.0, y = 0.0, z = 0.0;
            int entIndex = -1;

            ExtractJSONString(entry, "sound", sound, sizeof(sound));
            volume = ExtractJSONFloat(entry, "volume");
            pitch = ExtractJSONInt(entry, "pitch");
            level = ExtractJSONInt(entry, "level");
            x = ExtractJSONFloat(entry, "x");
            y = ExtractJSONFloat(entry, "y");
            z = ExtractJSONFloat(entry, "z");
            entIndex = ExtractJSONInt(entry, "ent");

            ExtractJSONString(entry, "name", name, sizeof(name));
            ExtractJSONString(entry, "class", className, sizeof(className));
            ExtractJSONString(entry, "pos", posString, sizeof(posString));  
            ExtractJSONString(entry, "model", model, sizeof(model));

            if (posString[0] != '\0')
            {
                // Remove brackets
                ReplaceString(posString, sizeof(posString), "[", "");
                ReplaceString(posString, sizeof(posString), "]", "");

                // Split by spaces
                char parts[3][32];
                int count = ExplodeString(posString, " ", parts, sizeof(parts), sizeof(parts[]));

                if (count >= 3)
                {
                    pos[0] = StringToFloat(parts[0]);
                    pos[1] = StringToFloat(parts[1]);
                    pos[2] = StringToFloat(parts[2]);
                }
            }

            if (sound[0] == '\0')
                continue;

            // --- Play sound ---
            // --- Check if sound is already precached ---
            int tbl = FindStringTable("soundprecache");
            if (tbl != INVALID_STRING_TABLE)
            {
                int idx = FindStringIndex(tbl, sound);
                if (idx == INVALID_STRING_INDEX)
                {
                    // Only precache if not already in table
                    PrecacheSound(sound, true);
                }
            }
            
            EmitAmbientSound(sound, pos, SOUND_FROM_WORLD, level, _, 1.0, pitch);
        }

        if (hRequest != INVALID_HANDLE) CloseHandle(hRequest);
        return 0;
    }

    stock bool:IsValidClient(iClient)
    {   
        if(iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
            return false;

        if(IsClientSourceTV(iClient) || IsClientReplay(iClient))
            return false;

        return true;
    }

    // --- SOUND EMIT CALLBACK ---
    public Action:CritWeaponSH(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
    {
        int client = entity;
        if (!IsValidEntity(entity))
            return Plugin_Continue;


        // Filtering logic
            if (StrContains(sample, "jockey", false) != -1)
                return Plugin_Continue; 
            if (StrContains(sample, "ambient", false) != -1)
                return Plugin_Continue; 
            float origin[3];
            GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);



            // Replace backslashes with forward slashes in the sample
            ReplaceString(sample, sizeof(sample), "\\", "/", false);
     
            // Build JSON body manually
            char json[8192];
            Format(json, sizeof(json),"{\"event\":\"sound\",\"sound\":{\"sound\":\"%s\",\"volume\":%.2f,\"pitch\":%d,\"level\":%d,\"pos\":\"[%.2f %.2f %.2f]\",\"name\":\"worldspawn\"}}",sample, volume, pitch, 95, origin[0], origin[1], origin[2]);

            // Send to both endpoints
            SendSoundHTTP(SOUND_URL_1, json);
            SendSoundHTTP(SOUND_URL_4, json);

            strcopy(g_szLastGlobalSound, sizeof(g_szLastGlobalSound), sample);  
            return Plugin_Continue;
    }

    // --- HTTP POST to Node.js ---
    void SendSoundHTTP(const char[] url, const char[] json)
    {
        Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
        if (hRequest == INVALID_HANDLE)
            return;

        SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-Type", "application/json");
        SteamWorks_SetHTTPRequestRawPostBody(hRequest, "application/json", json, strlen(json));
        SteamWorks_SetHTTPCallbacks(hRequest, OnSoundResponse);
        SteamWorks_SendHTTPRequest(hRequest);
    }

    // --- HTTP CALLBACK ---
    public int OnSoundResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
    {
        if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
            return 0;
        CloseHandle(hRequest);
        return 0;
    }

    public int OnHTTPResponse3(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data)
    {
        if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
        {
            PrintToServer("[SYNC] HTTP request failed or returned non-200: failure=%d success=%d code=%d", bFailure, bRequestSuccessful, eStatusCode);
            return 0;
        }

        int bodysize = 0;
        if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize) || bodysize <= 0)
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
        SteamWorks_GetHTTPResponseBodyData(hRequest, body, bodysize);
        body[bodysize] = '\0';

        if (strlen(body) == 0)
        {
            PrintToServer("[SYNC] HTTP body read but empty string");
            return 0;
        }

        int bodyLen = strlen(body);
        int pos = 0;

        while (pos < bodyLen)
        {
            // find next '{'
            int objStart = -1;
            for (int i = pos; i < bodyLen; i++)
            {
                if (body[i] == '{') { objStart = i; break; }
            }
            if (objStart == -1) break;

            // find matching '}' after objStart
            int objEnd = -1;
            for (int i = objStart + 1; i < bodyLen; i++)
            {
                if (body[i] == '}') { objEnd = i; break; }
            }
            if (objEnd == -1) break;

            // copy the object substring safely
            int len = objEnd - objStart + 1;
            if (len > 1023) len = 1023;
            char entry[1024];
            for (int i = 0; i < len; i++) entry[i] = body[objStart + i];
            entry[len] = '\0';

            pos = objEnd + 1; // advance

            // --- Extract fields safely (best-effort simple parsing) ---
            char name[MAX_NAME_LEN]; name[0] = '\0';
            char model[MAX_MODEL_LEN]; model[0] = '\0';
            char weaponModel[MAX_MODEL_LEN]; weaponModel[0] = '\0';
            float x = 0.0, y = 0.0, z = 0.0;
            float pitch = 0.0, yaw = 0.0, roll = 0.0;
            int skin = 0, animation = 0;
            float modelscale = 1.0;

            if (!ExtractJSONString(entry, "name", name, sizeof(name)))
            {
                PrintToServer("[SYNC] Skipping entry: missing name");
                continue;
            }

            ExtractJSONString(entry, "model", model, sizeof(model));
            ExtractJSONString(entry, "weapon_model", weaponModel, sizeof(weaponModel));

            x = ExtractJSONFloat(entry, "x");
            y = ExtractJSONFloat(entry, "y");
            z = ExtractJSONFloat(entry, "z");
            pitch = ExtractJSONFloat(entry, "pitch");
            yaw = ExtractJSONFloat(entry, "yaw");
            roll = ExtractJSONFloat(entry, "roll");
            skin = ExtractJSONInt(entry, "skin");
            animation = ExtractJSONInt(entry, "animation");

            // optional scale key (key name "scale" used by GMod; accept both)
            float maybeScale = ExtractJSONFloat(entry, "scale");
            if (maybeScale > 0.0) modelscale = maybeScale;
            else
            {
                maybeScale = ExtractJSONFloat(entry, "modelScale");
                if (maybeScale > 0.0) modelscale = maybeScale;
            }

            // Find existing slot
            int idx = FindPlayerIndexTERROR(name);
            if (idx == -1)
            {
                idx = FindFreeSlotTERROR();
                if (idx == -1)
                {
                    continue;
                }

                
                // ### CHANGED: try to find an existing prop_dynamic_override for this player
                int ent = 0;
                int maxEdicts = GetMaxEntities();

                for (int i = 1; i <= maxEdicts; i++) // start from 1; 0 is world
                {
                    if (!IsValidEntity(i)) continue;

                    char classname[64];
                    GetEntityClassname(i, classname, sizeof(classname));

                    if (StrEqual(classname, "prop_dynamic_override"))
                    {
                        char existingName[64];
                        GetEntPropString(i, Prop_Data, "m_iName", existingName, sizeof(existingName));

                        if (StrContains(existingName, "terror_") != -1 && StrContains(existingName, name) != -1)
                        {
                            ent = i;
                            break; // Found an existing entity for this player
                        }
                    }
                }

                if (ent == 0)
                {
                    // No existing entity, create a new one
                    ent = CreateEntityByName("prop_dynamic_override");
                    if (ent <= 0)
                    {
                        PrintToServer("[SYNC] CreateEntityByName failed for '%s' (ent=%d)", name, ent);
                        continue;
                    }

                    char npcTargetName[64];
                    Format(npcTargetName, sizeof(npcTargetName), "terror_%s_%d", name, gUniqueNPCounter++);
                    // Assign a unique targetname so we can find/reuse it later
                    DispatchKeyValue(ent, "targetname", npcTargetName); 
                    DispatchKeyValue(ent, "health", "9999999");

                    // Use kleiner as default until model provided
                    SetEntityModel(ent, "models/survivors/survivor_gambler.mdl");
                }

                // set solid type & clientside animation (only once; avoid repeating to reduce flicker)
                SetEntProp(ent, Prop_Send, "m_nSolidType", 2);
                SetEntProp(ent, Prop_Data, "m_nSolidType", 2);
                SetEntProp(ent, Prop_Send, "m_bClientSideAnimation", true);

                float tpos[3]; tpos[0] = x; tpos[1] = y; tpos[2] = z;
                float tang[3]; tang[0] = pitch; tang[1] = yaw; tang[2] = roll;
                SafeTeleportSchedule(ent, tpos, tang, NULL_VECTOR);

                // set scale if available
                if (modelscale > 0.0)
                {
                    SetEntPropFloat(ent, Prop_Send, "m_flModelScale", modelscale);
                }

                strcopy(gPlayerNames3[idx], sizeof(gPlayerNames3[idx]), name);
                strcopy(gPlayerModels3[idx], sizeof(gPlayerModels3[idx]), model);
                strcopy(gPlayerWeapons3[idx], sizeof(gPlayerWeapons3[idx]), weaponModel);
                gPlayerPos3[idx][0] = x; gPlayerPos3[idx][1] = y; gPlayerPos3[idx][2] = z;

                gPlayerEnts3[idx] = ent;
                activePlayers3[idx] = true;
            }
            else
            {
                int ent = gPlayerEnts3[idx];
                char classname[64];
                if (IsValidEntity(ent)) {
                    GetEntityClassname(ent, classname, sizeof(classname));

                    if (!IsValidEntity(ent) || IsValidEntity(ent) && !StrContains(classname, "prop_dynamic_override", false))
                    {
                        gPlayerEnts3[idx] = 0;
                        continue;
                    }

                    float dt = UPDATE_INTERVAL;
                    float newPos[3];
                    newPos[0] = gPlayerPos3[idx][0] + (x - gPlayerPos3[idx][0]) * INTERP_SPEED * dt;
                    newPos[1] = gPlayerPos3[idx][1] + (y - gPlayerPos3[idx][1]) * INTERP_SPEED * dt;
                    newPos[2] = gPlayerPos3[idx][2] + (z - gPlayerPos3[idx][2]) * INTERP_SPEED * dt;
                    float angles[3]; angles[0] = pitch; angles[1] = yaw; angles[2] = roll;

                    SafeTeleportSchedule(ent, newPos, angles, NULL_VECTOR);

                    // update stored pos to target (not interpolated) so next interpolation is correct
                    gPlayerPos3[idx][0] = x; gPlayerPos3[idx][1] = y; gPlayerPos3[idx][2] = z;

                    // apply model scale if requested
                    if (modelscale > 0.0)
                    {
                        SetEntPropFloat(ent, Prop_Send, "m_flModelScale", modelscale);
                    }

                    activePlayers3[idx] = true;
                }
            }
        } // end while parsing objects

        // cleanup player slots 
        for (int i = 0; i < MAX_PLAYERS; i++)
        {
            if (gPlayerEnts3[i] != 0 && !activePlayers3[i])
            {
                if (IsValidEntity(gPlayerEnts3[i]))
                {
                    AcceptEntityInput(gPlayerEnts3[i], "Kill");
                }
                gPlayerEnts3[i] = 0;
            }
        }

        if (hRequest != INVALID_HANDLE) CloseHandle(hRequest);

        return 0;
    }