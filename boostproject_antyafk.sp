#pragma semicolon 1

/* [ Defines ] */
#define LoopValidClients(%1) for(int %1 = 1; %1 < MaxClients; %1++) if(IsValidClient(%1))
#define Timer_Spawn 				0
#define Timer_Menu 					1

#define Time_Connection 			0
#define Time_Kill 					1
#define Time_Current 				1

#define Timer_UpdateData 			240.0 			// Co ile sekund aktualizować dane po api

#define PLUGIN_VERSION 				"1.0.1"

/* [ Includes ] */
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <ripext>
#include <multicolors>

/* [ Variables ] */
enum struct eConfig {
	ConVar cvApiKey;
	ConVar cvTimer[2];
	ConVar cvAction;
	char sApiKey[64];
	float fTimer[2];
	int iAction;
	int iAttempts;
	ArrayList alBoosters;
	
	void Reset() {
		this.sApiKey = "";
		for (int i = 0; i < 2; i++)this.fTimer[i] = 0.0;
		this.iAction = 0;
		this.iAttempts = 0;
		this.alBoosters.Clear();
	}
}

enum struct ePlayer {
	Handle hTimer;
	float fSpawnPosition[3];
	bool bChecking;
	int iTime[2];
	int iSpectTime[2];
	int iAfkCounter;
	
	void Reset() {
		if (this.hTimer != null)this.hTimer = null;
		for (int i = 0; i < 3; i++)this.fSpawnPosition[i] = 0.0;
		this.bChecking = false;
		for (int i = 0; i < 2; i++) {
			this.iTime[i] = 0;
			this.iSpectTime[i] = 0;
		}
		this.iAfkCounter = 0;
	}
}

eConfig g_eConfig;
ePlayer g_ePlayer[MAXPLAYERS + 1];

#pragma newdecls required

/* [ Plugin Info ] */
public Plugin myinfo = {
	name = "[ CS:GO ] Anty AFK for BoostProject", 
	author = "Bioly", 
	description = "N/A", 
	version = PLUGIN_VERSION, 
	url = "[ github.com/Biolasek | spcode.pl ]"
};

public void OnPluginStart() {
	g_eConfig.cvApiKey = CreateConVar("boost_apikey", "API_KEY", "Klucz API ze strony");
	g_eConfig.cvTimer[Timer_Spawn] = CreateConVar("boost_spawntimer", "20", "Po ilu sekundach od odrodzenia gracza sprawdzić jego status gry", _, true);
	g_eConfig.cvTimer[Timer_Menu] = CreateConVar("boost_menutimer", "15", "Ile sekund będzie miał gracz na wybranie odpowiedniej opcji w menu", _, true);
	g_eConfig.cvAction = CreateConVar("boost_action", "0", "Co zrobić gry booster jest nieaktywny? [ 0 - kick | inne - długość bana w minutach ]", _, true);
	AutoExecConfig();
	
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	
	AddCommandListener(Listener_JoinTeam, "jointeam");
	
	g_eConfig.alBoosters = new ArrayList(MAXPLAYERS + 1);
}

public void OnConfigsExecuted() {
	g_eConfig.Reset();
	g_eConfig.cvApiKey.GetString(g_eConfig.sApiKey, sizeof(g_eConfig.sApiKey));
	g_eConfig.fTimer[Timer_Spawn] = g_eConfig.cvTimer[Timer_Spawn].FloatValue;
	g_eConfig.fTimer[Timer_Menu] = g_eConfig.cvTimer[Timer_Menu].FloatValue;
	g_eConfig.iAction = g_eConfig.cvAction.IntValue;
	
	if (strlen(g_eConfig.sApiKey) > 0) {
		AFK_UpdateArray();
		CreateTimer(Timer_UpdateData, Timer_UpdateApi, false, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	} else SetFailState("[ BoostProject ] Nie podano żadnego klucza api.");
}

public Action Timer_UpdateApi(Handle hTimer, bool bAttempts) {
	if (g_eConfig.iAttempts >= 5) {
		LogToFile("addons/sourcemod/logs/boostproject.txt", "Nie można było nawiązać połączenia z api.");
		SetFailState("[ BoostProject ] Nie można było nawiązać połączenia z api.");
	}
	
	if (bAttempts)g_eConfig.iAttempts++;
	AFK_UpdateArray();
}

public void OnClientPutInServer(int iClient) {
	g_ePlayer[iClient].Reset();
	g_ePlayer[iClient].iTime[Time_Connection] = GetTime();
}

public void OnClientDisconnect(int iClient) {
	if (!IsValidClient(iClient))
		return;
	
	char sSteamID[64];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	int iBooster = g_eConfig.alBoosters.FindString(sSteamID);
	if (iBooster != -1)g_eConfig.alBoosters.Erase(iBooster);
}

public Action Event_OnPlayerSpawn(Event eEvent, char[] sName, bool bDontBroadcast) {
	if (GameRules_GetProp("m_bWarmupPeriod"))
		return Plugin_Continue;
	
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	if (!IsValidClient(iClient))
		return Plugin_Continue;
	
	if (!IsPlayerAlive(iClient))
		return Plugin_Continue;
	
	if (g_ePlayer[iClient].hTimer != null) {
		g_ePlayer[iClient].hTimer = null;
	}
	
	GetClientAbsOrigin(iClient, g_ePlayer[iClient].fSpawnPosition);
	g_ePlayer[iClient].hTimer = CreateTimer(g_eConfig.fTimer[Timer_Spawn] + FindConVar("mp_freezetime").FloatValue, Timer_CheckPlayer, iClient, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Event_OnPlayerDeath(Event eEvent, char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(eEvent.GetInt("attacker"));
	if (!IsValidClient(iClient))
		return Plugin_Continue;
	
	g_ePlayer[iClient].iTime[Time_Kill] = GetTime();
	return Plugin_Continue;
}

public Action Timer_CheckPlayer(Handle hTimer, int iClient) {
	if (!IsValidClient(iClient))
		return Plugin_Stop;
	
	if (!IsClientBooster(iClient))
		return Plugin_Stop;
	
	if (!IsPlayerAlive(iClient))
		return Plugin_Stop;
	
	if (g_ePlayer[iClient].hTimer == null)
		return Plugin_Stop;
	
	float fCurrentPosition[3];
	GetClientAbsOrigin(iClient, fCurrentPosition);
	if (GetVectorDistance(fCurrentPosition, g_ePlayer[iClient].fSpawnPosition) > 200.0)
		return Plugin_Stop;
	
	AFK_CheckPlayer(iClient);
	return Plugin_Stop;
}

public Action Listener_JoinTeam(int iClient, char[] sCommand, int iArgs) {
	if (!IsValidClient(iClient))
		return Plugin_Continue;
	
	char sTeam[3];
	GetCmdArg(1, sTeam, sizeof(sTeam));
	int iTeam = StringToInt(sTeam);
	if (iTeam == CS_TEAM_SPECTATOR) {
		g_ePlayer[iClient].iSpectTime[Time_Connection] = GetTime();
	} else {
		int iTime = g_ePlayer[iClient].iSpectTime[Time_Connection] > 0 ? g_ePlayer[iClient].iSpectTime[Time_Connection]:GetTime();
		if (GetClientTeam(iClient) == CS_TEAM_SPECTATOR)g_ePlayer[iClient].iSpectTime[Time_Current] += (GetTime() - iTime);
	}
	return Plugin_Continue;
}

public Action Timer_TimeToCheck(Handle hTimer, int iClient) {
	if (!IsValidClient(iClient))
		return Plugin_Stop;
	
	if (!g_ePlayer[iClient].bChecking)
		return Plugin_Stop;
	
	AFK_ActionWithClient(iClient);
	return Plugin_Stop;
}

Menu Menu_CheckPlayer() {
	Menu mMenu = new Menu(Menu_CheckPlayerCallback);
	mMenu.SetTitle("[ # BoostProject :: Anty AFK # ]\n    ↳ Wybierz opcje która zawiera nazwe \"BoostProject\".\n ");
	
	int iRandom = GetRandomInt(0, 4);
	for (int i = 0; i < 5; i++) {
		if (i == iRandom)mMenu.AddItem("correct", "» BoostProject");
		else mMenu.AddItem("kick", "» Jestem afk B-)");
	}
	
	mMenu.ExitButton = false;
	return mMenu;
}

public int Menu_CheckPlayerCallback(Menu mMenu, MenuAction mAction, int iClient, int iPosition) {
	switch (mAction) {
		case MenuAction_Select: {
			char sItem[32];
			mMenu.GetItem(iPosition, sItem, sizeof(sItem));
			if (!IsValidClient(iClient) || !g_ePlayer[iClient].bChecking) {
				return;
			}
			
			if (StrEqual(sItem, "correct")) {
				g_ePlayer[iClient].bChecking = false;
				CPrintToChat(iClient, "\x04BoostProject \x08» \x01Udało Ci się przejść test, miej się jednak na baczności.");
				if (g_ePlayer[iClient].hTimer != null)g_ePlayer[iClient].hTimer = null;
				g_ePlayer[iClient].hTimer = CreateTimer(g_eConfig.fTimer[Timer_Spawn], Timer_CheckPlayer, iClient, TIMER_FLAG_NO_MAPCHANGE);
			} else AFK_ActionWithClient(iClient);
		}
		case MenuAction_End:delete mMenu;
	}
}

/* [ Helpers ] */
bool IsValidClient(int iClient) {
	if (iClient <= 0)return false;
	if (iClient > MaxClients)return false;
	if (!IsClientConnected(iClient))return false;
	if (IsFakeClient(iClient))return false;
	if (IsClientSourceTV(iClient))return false;
	return IsClientInGame(iClient);
}

void AFK_CheckPlayer(int iClient) {
	if (!IsValidClient(iClient))
		return;
	
	g_ePlayer[iClient].iAfkCounter++;
	g_ePlayer[iClient].bChecking = true;
	CPrintToChat(iClient, "\x0F⌈︎⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\x01»⠀\x0FANTY AFK⠀\x01«⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\x0F⌉︎");
	CPrintToChat(iClient, "⠀⠀\x08» \x01Sprawdzamy czy jesteś AFK.");
	CPrintToChat(iClient, "⠀⠀\x08» \x01Jeśli nie wyświetliło Ci się menu wpisz \x08!afk\x01.");
	CPrintToChat(iClient, "\x0F⌊⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\x01»⠀\x0FANTY AFK⠀\x01«⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\x0F⌋︎");
	CreateTimer(g_eConfig.fTimer[Timer_Menu], Timer_TimeToCheck, iClient, TIMER_FLAG_NO_MAPCHANGE);
	Menu_CheckPlayer().Display(iClient, RoundToFloor(g_eConfig.fTimer[Timer_Menu]));
}

void AFK_ActionWithClient(int iClient) {
	if (!g_eConfig.iAction)KickClient(iClient, "[ BoostProject ] Zostałeś wyrzucony z powodu nieaktywności.");
	else {
		char sReason[256];
		Format(sReason, sizeof(sReason), "[ BoostProject ] Zostałeś zbanowany na %d minut. Powód: AFK.", g_eConfig.iAction);
		BanClient(iClient, g_eConfig.iAction, BANFLAG_AUTO, sReason, sReason);
	}
}

void AFK_UpdateArray() {
	PrintToServer("[ BoostProject ] Próba nawiązania połączenia z api.");
	
	char sApi[PLATFORM_MAX_PATH];
	Format(sApi, sizeof(sApi), "https://api.boostproject.pro/plugin/send-data");
	HTTPRequest rRequest = new HTTPRequest(sApi);
	
	JSONObject joHead = new JSONObject();
	joHead.SetString("version", PLUGIN_VERSION);
	
	JSONArray jaPlayerArray = new JSONArray();
	LoopValidClients(i) {
		char sSteamID[64], sName[MAX_NAME_LENGTH], sTeam[12];
		GetClientAuthId(i, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
		GetClientName(i, sName, sizeof(sName));
		
		int iTime[2];
		for (int j = 0; j < 2; j++) {
			iTime[j] = g_ePlayer[i].iTime[j] > 0 ? g_ePlayer[i].iTime[j]:GetTime();
			iTime[j] = (GetTime() - iTime[j]);
		}
		
		switch (GetClientTeam(i)) {
			case CS_TEAM_CT:Format(sTeam, sizeof(sTeam), "CT");
			case CS_TEAM_T:Format(sTeam, sizeof(sTeam), "TT");
			case CS_TEAM_SPECTATOR:Format(sTeam, sizeof(sTeam), "SPECT");
		}
		
		JSONObject joPlayer = new JSONObject();
		joPlayer.SetString("steamid64", sSteamID);
		joPlayer.SetString("name", sName);
		joPlayer.SetInt("kills", GetEntProp(i, Prop_Data, "m_iFrags"));
		joPlayer.SetInt("deaths", GetEntProp(i, Prop_Data, "m_iDeaths"));
		joPlayer.SetInt("assists", CS_GetClientAssists(i));
		joPlayer.SetInt("seconds", iTime[Time_Connection]);
		joPlayer.SetInt("killSeconds", iTime[Time_Kill]);
		joPlayer.SetInt("connectionTime", g_ePlayer[i].iTime[Time_Connection]);
		joPlayer.SetInt("killTime", g_ePlayer[i].iTime[Time_Kill]);
		joPlayer.SetInt("killSeconds", iTime[Time_Kill]);
		joPlayer.SetInt("spectSeconds", g_ePlayer[i].iSpectTime[Time_Current]);
		joPlayer.SetString("team", sTeam);
		joPlayer.SetInt("afkCounter", g_ePlayer[i].iAfkCounter);
		jaPlayerArray.Push(joPlayer);
		delete joPlayer;
	}
	
	joHead.Set("players", jaPlayerArray);
	joHead.SetString("key", g_eConfig.sApiKey);
	rRequest.Post(joHead, OnPlayersReceived);
	
	delete jaPlayerArray;
	delete joHead;
}

void OnPlayersReceived(HTTPResponse rResponse, any aValue) {
	if (rResponse.Status != HTTPStatus_OK) {
		CreateTimer(5.0, Timer_UpdateApi, true, TIMER_FLAG_NO_MAPCHANGE);
		LogToFile("addons/sourcemod/logs/boostproject.txt", "Próba nawiązania połączenia z api nie powiodła się ( Status: %d )", rResponse.Status);
		PrintToServer("[ BoostProject ] Próba nawiązania połączenia z api nie powiodła się ( Status: %d )", rResponse.Status);
		return;
	}
	
	/* [ { "steamid64": "1234566789081723614", "msg": "Zarobiłes 100 kredytow" }, { "steamid64": "098765432123345", "msg": "" } ] */
	JSONArray jaBoosters = view_as<JSONArray>(rResponse.Data);
	JSONObject joBooster;
	char sMessage[MAX_MESSAGE_LENGTH], sSteamID[64];
	for (int i = 0; i < jaBoosters.Length; i++) {
		joBooster = view_as<JSONObject>(jaBoosters.Get(i));
		joBooster.GetString("steamid64", sSteamID, sizeof(sSteamID));
		joBooster.GetString("msg", sMessage, sizeof(sMessage));
		
		int iBooster = g_eConfig.alBoosters.FindString(sSteamID);
		if (iBooster == -1)g_eConfig.alBoosters.PushString(sSteamID);
		
		if (strlen(sMessage) > 0) {
			int iClient = FindPlayerBySteamID(sSteamID);
			if (!IsValidClient(iClient))
				return;
			
			PrintToChat(iClient, "\x04BoostProject \x08» \x01%s.", sMessage);
		}
	}
	delete joBooster;
	delete jaBoosters;
}

bool IsClientBooster(int iClient) {
	if (!IsValidClient(iClient))return false;
	
	char sSteamID[64];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	int iBooster = g_eConfig.alBoosters.FindString(sSteamID);
	return iBooster == -1 ? false:true;
}

int FindPlayerBySteamID(char[] sSteamID) {
	char sBuffer[64];
	LoopValidClients(i) {
		GetClientAuthId(i, AuthId_SteamID64, sBuffer, sizeof(sBuffer));
		if (StrEqual(sSteamID, sBuffer))
			return i;
	}
	return 0;
} 