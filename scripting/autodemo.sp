#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdktools>

#include <autodemo>
#include <SteamWorks>

#pragma newdecls required
#pragma tabsize 4

// autodemo.sp
public Plugin myinfo =
{ 
	name = "[Auto Demo] Core",
	author = "Wend4r",
	description = "Record and upload SourceTV demos.",
	version = "1.0.0 Alpha",
	url = "Discord: Wend4r#0001 | VK: vk.com/wend4r"
};

int 	g_iAccountID[MAXPLAYERS + 1],
		m_vecOrigin,
		m_angRotation;

char	g_sAPIKey[128],
		g_sDemoPath[PLATFORM_MAX_PATH],
		g_sPort[8],
		g_sWEBSite[256];

ConVar  g_hTVEnable,
		g_hTVAutoRecord,
		g_hTVAutoRetry;

public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] sError, int iErrorSize)
{
	CreateNative("AutoDemo_SendHTTPQuery", Native_SendHTTPQuery);

	RegPluginLibrary("autodemo");

	return APLRes_Success;
}

int Native_SendHTTPQuery(Handle hPlugin, int iArgs)
{
	int iLenght = GetNativeCell(2);

	decl char sEventName[128];

	char[] sParams = new char[iLenght];

	GetNativeString(1, sEventName, sizeof(sEventName));
	FormatNativeString(0, 3, 4, iLenght, _, sParams);
	SendHTTPQuery(sEventName, sizeof(sEventName) + iLenght, _, "%s", sParams);
}

public void OnPluginStart()
{
	IntToString(FindConVar("hostport").IntValue, g_sPort, sizeof(g_sPort));

	(g_hTVEnable = FindConVar("tv_enable")).AddChangeHook(OnConVarChange);
	g_hTVEnable.SetInt(1);

	(g_hTVAutoRecord = FindConVar("tv_autorecord")).AddChangeHook(OnConVarChange);
	g_hTVAutoRecord.SetInt(1);

	(g_hTVAutoRetry = FindConVar("tv_autoretry")).AddChangeHook(OnConVarChange);
	g_hTVAutoRetry.SetInt(1);

	m_vecOrigin = FindSendPropInfo("CBaseEntity", "m_vecOrigin");
	m_angRotation = FindSendPropInfo("CBaseEntity", "m_angRotation");

	LoadSettings();

	RegAdminCmd("sm_autodemo_reload", ConfigReload, ADMFLAG_CONFIG);

	HookEvent("game_end", OnGameEnd, EventHookMode_Pre);
	HookEvent("bomb_planted", OnBombEvents);
	HookEvent("bomb_exploded", OnBombEvents);
	HookEvent("bomb_defused", OnBombEvents);
	HookEvent("begin_new_match", OnMatchEvents, EventHookMode_PostNoCopy);
	HookEvent("cs_intermission", OnMatchEvents, EventHookMode_PostNoCopy);
	HookEvent("cs_match_end_restart", OnMatchEvents, EventHookMode_PostNoCopy);
	HookEvent("round_start", OnMatchEvents, EventHookMode_Pre);
	HookEvent("round_end", OnRoundEnd);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_team", OnPlayerTeam, EventHookMode_Pre);
	HookEvent("player_say", OnPlayerSay);

	static char sSteamID[32];

	for(int i = MaxClients + 1; --i;)
	{
		if(IsClientInGame(i))
		{
			GetClientAuthId(i, AuthId_Steam2, sSteamID, sizeof(sSteamID));
			OnClientAuthorized(i, sSteamID);
		}
	}

	SendHTTPQuery("plugin_start", _, true);
}

public void OnConfigsExecuted()
{
	if(GetFeatureStatus(FeatureType_Native, "SteamWorks_GetPublicIPCell"))
	{
		static char sCurrentMap[128];

		GetCurrentMapEx(sCurrentMap, sizeof(sCurrentMap));
		SendHTTPQuery("map_start", 160, _, "\"name\": \"%s\"", sCurrentMap);

		FileType	iFileType;

		static char sFileName[PLATFORM_MAX_PATH],
					sNewDirectory[PLATFORM_MAX_PATH];

		static ArrayList hDemos;

		DirectoryListing hDirectory;

		if(!g_sDemoPath[0])
		{
			BuildPath(Path_SM, g_sDemoPath, sizeof(g_sDemoPath), "data/demos/");

			if(!DirExists(g_sDemoPath))
			{
				CreateDirectory(g_sDemoPath, FPERM_O_READ | FPERM_O_EXEC | FPERM_G_EXEC | FPERM_G_READ | FPERM_U_EXEC | FPERM_U_WRITE | FPERM_U_READ);
			}
		}

		if(!hDemos)
		{
			hDemos = new ArrayList(PLATFORM_MAX_PATH / 4 + 1);
		}
		else
		{
			hDemos.Clear();
		}

		hDirectory = OpenDirectory(g_sDemoPath);

		while(hDirectory.GetNext(sFileName, sizeof(sFileName), iFileType))
		{
			if(iFileType == FileType_File)
			{
				hDemos.PushString(sFileName);
			}
		}

		int iLength = hDemos.Length;

		if(iLength)
		{
			char[] sDemoFiles = new char[iLength * PLATFORM_MAX_PATH];

			for(int i = 0; i != iLength; i++)
			{
				hDemos.GetString(i, sFileName, sizeof(sFileName));
				FormatEx(sDemoFiles[strlen(sDemoFiles)], PLATFORM_MAX_PATH, "\"%s\", ", sFileName);
			}

			sDemoFiles[strlen(sDemoFiles) - 2] = '\0';

			SendHTTPQuery("demo_unload", strlen(sDemoFiles) + 64, _, "\"time_limit\": %i, \"files\": [%s]", iLength * 360, sDemoFiles);

		}

		hDirectory.Close();
		hDirectory = OpenDirectory("/");

		while(hDirectory.GetNext(sFileName, sizeof(sFileName), iFileType))
		{
			if(iFileType == FileType_File && !strncmp(sFileName, "auto", 4) && '0' <= (sFileName[4] & 0xFF) <= '9')
			{
				FormatEx(sNewDirectory, sizeof(sNewDirectory), "%sauto%c-%i-%i-%s-%s.dem", g_sDemoPath, sFileName[4], GetFileTime(sFileName, FileTime_LastChange), SteamWorks_GetPublicIPCell(), g_sPort, sCurrentMap);
				RenameFile(sNewDirectory, sFileName);
			}
		}

		hDirectory.Close();
	}
}

void LoadSettings()
{
	KeyValues hSettings = new KeyValues("AutoDemo");

	static char sFilePath[PLATFORM_MAX_PATH];

	if(!sFilePath[0])
	{
		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/autodemo.txt");
	}

	if(!hSettings.ImportFromFile(sFilePath)) 
	{
		SetFailState("Missing configuration file: %s", sFilePath); 
	}

	hSettings.GotoFirstSubKey();
	hSettings.Rewind();

	hSettings.GetString("web_site", g_sWEBSite, sizeof(g_sWEBSite));
	hSettings.GetString("web_key", g_sAPIKey, sizeof(g_sAPIKey));

	hSettings.Close();
}

Action ConfigReload(int iClient, int iArgs)
{
	LoadSettings();

	return Plugin_Handled;
}

void GetCurrentMapEx(char[] sMapBuffer, int iSize)
{
	decl char sBuffer[256];

	GetCurrentMap(sBuffer, sizeof(sBuffer));

	int iIndex = -1, iLen = strlen(sBuffer);
	
	for(int i = 0; i != iLen; i++)
	{
		if(sBuffer[i] == '/' || sBuffer[i] == '\\')
		{
			iIndex = i;
		}
	}

	strcopy(sMapBuffer, iSize, sBuffer[iIndex + 1]);
}

void OnBombEvents(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if(iClient)
	{
		SendHTTPQuery(sName, 128, _, "\"player\": {\"name\": \"%N\", \"accounid\": %i}", iClient, g_iAccountID[GetClientOfUserId(hEvent.GetInt("userid"))]);
	}
}

void OnMatchEvents(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	SendHTTPQuery(sName);
}

void OnRoundEnd(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	static char sMessage[64];

	hEvent.GetString("message", sMessage, sizeof(sMessage));

	SendHTTPQuery(sName, 256, _, "\"winner\": %i, \"message\": \"%s\", \"player_count\": %i, \"score_t\": %i, \"score_ct\": %i", hEvent.GetInt("winner"), sMessage, hEvent.GetInt("player_count"), CS_GetTeamScore(CS_TEAM_T), CS_GetTeamScore(CS_TEAM_CT));
}

void OnGameEnd(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	ServerCommand("tv_stop; tv_record %s", g_sDemoPath);
	SendHTTPQuery(sName, 64, _, "\"winner\": %i", hEvent.GetInt("winner"));
	OnConfigsExecuted();
}

void OnPlayerDeath(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	int iAttacker = GetClientOfUserId(hEvent.GetInt("attacker")),
		iAssister = GetClientOfUserId(hEvent.GetInt("assister")),
		iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if(iAttacker && iClient)
	{
		static float flAttackerOrigin[3],
					 flClientOrigin[3],
					 flAttackerRotation[3],
					 flClientRotation[3];

		static char  sWeapon[32],
					 sItemID[128];

		hEvent.GetString("weapon", sWeapon, sizeof(sWeapon));
		hEvent.GetString("weapon_itemid", sItemID, sizeof(sItemID));

		GetEntDataVector(iAttacker, m_vecOrigin, flAttackerOrigin);
		GetEntDataVector(iClient, m_vecOrigin, flClientOrigin);

		GetEntDataVector(iAttacker, m_angRotation, flAttackerRotation);
		GetEntDataVector(iClient, m_angRotation, flClientRotation);

		SendHTTPQuery(sName, 512, _, "\"attacker\": {\"name\": \"%N\", \"accounid\": %i, \"team\": %i, \"rotation\": \"%f\", \"origin\": {\"x\": \"%f\", \"y\": \"%f\", \"z\": \"%f\"}}, \"assister\": {\"name\": \"%N\", \"accounid\": %i, \"team\": %i}, \"assistedflash\": %i, \"weapon\": \"%s\", \"weapon_itemid\": %s, \"headshot\": %i, \"penetrated\": %i, \"victim\": {\"name\": \"%N\", \"accounid\": %i, \"team\": %i, \"rotation\": \"%f\", \"origin\": {\"x\": \"%f\", \"y\": \"%f\", \"z\": \"%f\"}}", iAttacker, g_iAccountID[iAttacker], GetClientTeam(iAttacker), flAttackerRotation[1], flAttackerOrigin[0], flAttackerOrigin[1], flAttackerOrigin[2], iAssister, g_iAccountID[iAssister], iAssister ? GetClientTeam(iAssister) : 0, hEvent.GetBool("assistedflash"), sWeapon, sItemID[0] == '\0' ? "0" : sItemID, hEvent.GetBool("headshot"), hEvent.GetBool("penetrated"), iClient, g_iAccountID[iClient], GetClientTeam(iClient), flAttackerRotation[1], flClientOrigin[0], flClientOrigin[1], flClientOrigin[2]);
	}
}

void OnPlayerTeam(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if(iClient)
	{
		SendHTTPQuery(sName, 512, _, "\"player\": {\"name\": \"%N\", \"accounid\": %i}, \"disconnect\": %i, \"oldteam\": %i, \"team\": %i, \"autobalance\": %i", iClient, g_iAccountID[iClient], hEvent.GetInt("disconnect"), hEvent.GetInt("oldteam"), hEvent.GetInt("team"), hEvent.GetInt("autoteam"));
	}
}

void OnPlayerSay(Event hEvent, const char[] sName, bool bBroadcastDisabled)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if(iClient)
	{
		static char sMessage[254];

		hEvent.GetString("text", sMessage, sizeof(sMessage));
		SendHTTPQuery(sName, 512, _, "\"player\": {\"name\": \"%N\", \"accounid\": %i, \"isalive\": %i, \"team\": %i}, \"message\": \"%s\"", iClient, g_iAccountID[iClient], IsPlayerAlive(iClient), GetClientTeam(iClient), sMessage);
	}
}

public void OnClientAuthorized(int iClient, const char[] sAuth)
{
	g_iAccountID[iClient] = sAuth[0] == 'S' && sAuth[7] == ':' ? (StringToInt(sAuth[10]) << 1 | sAuth[8] - '0') : 0;
}

void OnConVarChange(ConVar hCvar, const char[] sOldValue, const char[] sNewValue)
{
	if(sNewValue[0] != '1')
	{
		hCvar.SetInt(1);
	}
}

void SendHTTPQuery(const char[] sEventName, int iSize = 0, bool bFailState = false, const char[] sFormat = NULL_STRING, any ...)
{
	int iSizeof = iSize + 128;

	// #pragma dynamic 32768

	char[] sData = new char[iSizeof];

	FormatEx(sData, iSizeof, "{\"event\": \"%s\"", sEventName);

	if(sFormat[0])
	{
		int iLen = strlen(sData);

		char[] sParams = new char[iSize];

		VFormat(sParams, iSize, sFormat, 5);
		FormatEx(sData[iLen], iSizeof - iLen, ", \"params\": {%s}", sParams);
	}

	sData[strlen(sData)] = '}';

	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, g_sWEBSite);

	// LogMessage("\"key\": \"%s\"; \"port\": \"%s\"; \"data\": \"%s\"", g_sAPIKey, g_sPort, sData);

	if(hRequest)
	{
		SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "key", g_sAPIKey);
		SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "port", g_sPort);
		SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "data", sData);

		SteamWorks_SetHTTPCallbacks(hRequest, OnRequestCallback);

		if(bFailState)
		{
			SteamWorks_SetHTTPRequestContextValue(hRequest, true);
		}

		if(!SteamWorks_SendHTTPRequest(hRequest))
		{
			hRequest.Close();
		}
	}
	else
	{
		LogError("Error reading URL - \"%s\"", g_sWEBSite);
	}
}

void OnRequestCallback(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode iStatusCode, bool bFirstCheck)
{
	if(iStatusCode && k_EHTTPStatusCode307TemporaryRedirect < iStatusCode)
	{
		static const char sError[] = "\"%s\": HTTP_ERR %i (%i, %i)";

		if(bFirstCheck)
		{
			SetFailState(sError, g_sWEBSite, iStatusCode, bFailure, bRequestSuccessful);
		}
		else
		{
			LogError(sError, g_sWEBSite, iStatusCode, bFailure, bRequestSuccessful);
		}
	}

	hRequest.Close();
}

public void OnPluginEnd()
{
	SendHTTPQuery("plugin_end");
}