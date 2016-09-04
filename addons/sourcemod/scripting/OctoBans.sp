#pragma semicolon 1
#include <sourcemod>
#include <SteamWorks>
#include <smjansson>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required
#include <base64>

#define PLUGIN_VERSION	"1.0 beta"

public Plugin myinfo =
{
	name        = "Octo Bans",
	author      = "R1KO",
	version     = PLUGIN_VERSION,
	url         = "http://hlmod.ru"
};

#define UID(%0) GetClientUserId(%0)
#define CID(%0) GetClientOfUserId(%0)

#define DEBUG_MODE 0

#if DEBUG_MODE 1

static const char g_szDebugLogFile[] = "addons/sourcemod/logs/OctoBans_Debug.log";

stock void DebugMsg(const char[] szMsg, any ...)
{
	char szBuffer[512];
	VFormat(szBuffer, sizeof(szBuffer), szMsg, 2);
	LogToFile(g_szDebugLogFile, szBuffer);
}

#define DebugMessage(%0) DebugMsg(%0);
#else
#define DebugMessage(%0)
#endif

int g_iServerID;
bool g_bCheckServerID;
char g_szHost[128];
char g_szAuthorizationHash[256];
char g_szBanURL[128];

int g_iBanTarget[MAXPLAYERS+1];
int g_iBanTime[MAXPLAYERS+1];
/*
bool g_bWaitChat[MAXPLAYERS+1];
char g_szFindValue[MAXPLAYERS+1][64];
*/
KeyValues g_hKeyValues;

TopMenu g_hTopMenu;

public void OnLibraryRemoved(const char[] szName)
{
	if (strcmp(szName, "adminmenu") == 0) 
	{
		g_hTopMenu = null;
	}
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	TopMenu hTopMenu;
	if (LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(hTopMenu);
	}
}

public void OnAdminMenuReady(Handle hSourceTopMenu)
{
	TopMenu hTopMenu = TopMenu.FromHandle(hSourceTopMenu);

	if (g_hTopMenu == hTopMenu)
	{
		return;
	}

	g_hTopMenu = hTopMenu;

	TopMenuObject TopMenuCategory = g_hTopMenu.FindCategory(ADMINMENU_PLAYERCOMMANDS);

	if (TopMenuCategory != INVALID_TOPMENUOBJECT)
	{
		g_hTopMenu.AddItem("sm_ban", AdminMenu_Ban, TopMenuCategory, "sm_ban", ADMFLAG_BAN);
	}
}

public void AdminMenu_Ban(Handle hTopMenu, TopMenuAction action, TopMenuObject topobj_id, int iClient, char[] szBuffer, int iMaxLength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		FormatEx(szBuffer, iMaxLength, "Забанить игрока");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayBanTargetMenu(iClient);
	}
}

void DisplayBanTargetMenu(int iClient)
{
	Menu hMenu = CreateMenu(MenuHandler_BanPlayerList);

	hMenu.SetTitle("Выберите игрока:\n ");
	hMenu.ExitBackButton = true;

	AddTargetsToMenu2(hMenu, iClient, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_BanPlayerList(Menu hMenu, MenuAction action, int iClient, int Item)
{
	switch(action)
	{
	case MenuAction_End:
		{
			delete hMenu;
		}
	case MenuAction_Cancel:
		{
			if (Item == MenuCancel_ExitBack && g_hTopMenu)
			{
				g_hTopMenu.Display(iClient, TopMenuPosition_LastCategory);
			}
		}
	case MenuAction_Select:
		{
			char szUserID[16];
			hMenu.GetItem(Item, szUserID, sizeof(szUserID));
			
			int iUserID = StringToInt(szUserID);
			int iTarget = GetClientOfUserId(iUserID);

			if (iTarget == 0)
			{
				PrintToChat(iClient, "[SM] %t", "Player no longer available");
			}
			else if (!CanUserTarget(iClient, iTarget))
			{
				PrintToChat(iClient, "[SM] %t", "Unable to target");
			}
			else
			{
				g_iBanTarget[iClient] = iUserID;
				DisplayBanTimeMenu(iClient);
			}
		}
	}
	
	return 0;
}

void DisplayBanTimeMenu(int iClient)
{
	Menu hMenu = CreateMenu(MenuHandler_BanTimeList);

	hMenu.SetTitle("Выберите срок:\n ");
	hMenu.ExitBackButton = true;
	
	g_hKeyValues.Rewind();
	if(g_hKeyValues.JumpToKey("ban_times") && g_hKeyValues.GotoFirstSubKey(false))
	{
		char szTime[16], szTimeDisplay[64];
		do
		{
			g_hKeyValues.GetSectionName(szTime, sizeof(szTime));
			g_hKeyValues.GetString(NULL_STRING, szTimeDisplay, sizeof(szTimeDisplay));
			hMenu.AddItem(szTime, szTimeDisplay);
		} while (g_hKeyValues.GotoNextKey(false));
	}

	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_BanTimeList(Menu hMenu, MenuAction action, int iClient, int Item)
{
	switch(action)
	{
	case MenuAction_End:
		{
			delete hMenu;
		}
	case MenuAction_Cancel:
		{
			if (Item == MenuCancel_ExitBack && g_hTopMenu)
			{
				DisplayBanTargetMenu(iClient);
			}
		}
	case MenuAction_Select:
		{
			if (GetClientOfUserId(g_iBanTarget[iClient]) == 0)
			{
				PrintToChat(iClient, "[SM] %t", "Player no longer available");
			}
			else
			{
				char szTime[16];
				hMenu.GetItem(Item, szTime, sizeof(szTime));
				g_iBanTime[iClient] = StringToInt(szTime);
				DisplayBanReasonMenu(iClient);
			}
		}
	}
	
	return 0;
}

void DisplayBanReasonMenu(int iClient)
{
	Menu hMenu = CreateMenu(MenuHandler_BanReasonList);

	hMenu.SetTitle("Выберите причину:\n ");
	hMenu.ExitBackButton = true;
	
	g_hKeyValues.Rewind();
	if(g_hKeyValues.JumpToKey("ban_reasons") && g_hKeyValues.GotoFirstSubKey(false))
	{
		char szReason[128], szReasonDisplay[128];
		do
		{
			g_hKeyValues.GetSectionName(szReason, sizeof(szReason));
			g_hKeyValues.GetString(NULL_STRING, szReasonDisplay, sizeof(szReasonDisplay));
			hMenu.AddItem(szReason, szReasonDisplay);
		} while (g_hKeyValues.GotoNextKey(false));
	}

	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_BanReasonList(Menu hMenu, MenuAction action, int iClient, int Item)
{
	switch(action)
	{
	case MenuAction_End:
		{
			delete hMenu;
		}
	case MenuAction_Cancel:
		{
			if (Item == MenuCancel_ExitBack && g_hTopMenu)
			{
				DisplayBanTargetMenu(iClient);
			}
		}
	case MenuAction_Select:
		{
			int iTarget = GetClientOfUserId(g_iBanTarget[iClient]);
			if (iTarget == 0)
			{
				PrintToChat(iClient, "[SM] %t", "Player no longer available");
			}
			else
			{
				char szReason[128];
				hMenu.GetItem(Item, szReason, sizeof(szReason));

				UTIL_CreateBan(iTarget, _, _, _, iClient, _, g_iBanTime[iClient]*60, szReason);
			}
		}
	}
	
	return 0;
}

public void OnConfigsExecuted()
{
	g_iServerID = 1;
	g_szHost[0] =
	g_szBanURL[0] =
	g_szAuthorizationHash[0] = 0;

	if(g_hKeyValues != null)
	{
		delete g_hKeyValues;
	}

	g_hKeyValues = new KeyValues("OctoBans");
	
	char szBuffer[256];
	BuildPath(Path_SM, szBuffer, sizeof(szBuffer), "configs/octobans.ini");
	if(!g_hKeyValues.ImportFromFile(szBuffer))
	{
		SetFailState("Не удалось открыть файл '%s'", szBuffer);
		return;
	}

	g_hKeyValues.Rewind();
	if(g_hKeyValues.JumpToKey("settings"))
	{
		g_iServerID = g_hKeyValues.GetNum("server_id", 1);
		g_bCheckServerID = view_as<bool>(g_hKeyValues.GetNum("check_server_id"));
		g_hKeyValues.GetString("host", g_szHost, sizeof(g_szHost));
		g_hKeyValues.GetString("ban_url", g_szBanURL, sizeof(g_szBanURL));

		char szLogin[128], szPassword[128];
		g_hKeyValues.GetString("login", szLogin, sizeof(szLogin));
		g_hKeyValues.GetString("password", szPassword, sizeof(szPassword));
		if(szLogin[0] && szPassword[0])
		{
			FormatEx(szBuffer, sizeof(szBuffer), "%s:%s", szLogin, szPassword);
			EncodeBase64(g_szAuthorizationHash, sizeof(g_szAuthorizationHash), szBuffer);
			Format(g_szAuthorizationHash, sizeof(g_szAuthorizationHash), "Basic %s", g_szAuthorizationHash);
		}
		else
		{
			LogMessage("Авторизация отключена");
		}
	}
	else
	{
		SetFailState("Не найдена секция 'settings'");
		return;
	}
}

void UTIL_CreateBan(int iSourceClient = 0, const char[] szSourceSteamId64 = "", const char[] szSourceName = "", const char[] szSourceIp = "", int iAdmin = 0, int iType = 0, int iDuration, const char[] szReason)
{
	DebugMessage("UTIL_CreateBan -> iSourceClient: %i, iAdmin: %i", iSourceClient, iAdmin)

	char szName[64], szIp[24], szBuffer[512], szSteamId64[32], szAdminSteamId64[32];

	if(iAdmin)
	{
		GetClientAuthId(iAdmin, AuthId_SteamID64, szAdminSteamId64, sizeof(szAdminSteamId64));
	}
	else
	{
		strcopy(szAdminSteamId64, sizeof(szAdminSteamId64), "0");
	}

	if(iSourceClient)
	{
		GetClientAuthId(iSourceClient, AuthId_SteamID64, szSteamId64, sizeof(szSteamId64));
		GetClientName(iSourceClient, szName, sizeof(szName));
		GetClientIP(iSourceClient, szIp, sizeof(szIp));
	}
	else
	{
		strcopy(szSteamId64, sizeof(szSteamId64), szSourceSteamId64);
		strcopy(szName, sizeof(szName), szSourceName);
		strcopy(szIp, sizeof(szIp), szSourceIp);
	}

	FormatEx(szBuffer, sizeof(szBuffer), "http://%s/api/bans/add", g_szHost);

	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, szBuffer);
	if (hRequest)
	{
		SteamWorks_SetHTTPRequestContextValue(hRequest, UID(iAdmin));
		SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Accept", "application/json");

		if(g_szAuthorizationHash[0])
		{
			SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Authorization", g_szAuthorizationHash);
		}

		FormatEx(szBuffer, sizeof(szBuffer), "pid=%s&ip=%s&nick=%s&aid=%s&type=%i&duration=%i&reason=%s&serverid=%i", szSteamId64, szIp, szName, szAdminSteamId64, iType, iDuration, szReason, g_iServerID);

		DebugMessage(szBuffer)
		SteamWorks_SetHTTPRequestRawPostBody(hRequest, "application/x-www-form-urlencoded", szBuffer, strlen(szBuffer)+4);
		
		if (!SteamWorks_SetHTTPCallbacks(hRequest, OnTransferComplete) || !SteamWorks_SendHTTPRequest(hRequest))
		{
			delete hRequest;
			LogError("Failed Request (UTIL_CreateBan: %s)", szSteamId64);
		}
	}
	else
	{
		LogError("Failed CreateHTTPRequest (UTIL_CreateBan: %s)", szSteamId64);
	}
}

stock void UTIL_RemoveBan(const char[] szBanID, int iClient = 0)
{
	DebugMessage("UTIL_RemoveBan -> szBanID: %s, iClient: %i", szBanID, iClient)

	char szBuffer[256];

	FormatEx(szBuffer, sizeof(szBuffer), "http://%s/api/bans/delete/%s", g_szHost, szBanID);

	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodDELETE, szBuffer);
	if (hRequest)
	{
	//	SteamWorks_SetHTTPRequestContextValue(hRequest, UID(iClient));
		SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Accept", "application/json");

		if(g_szAuthorizationHash[0])
		{
			SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Authorization", g_szAuthorizationHash);
		}

		if (!SteamWorks_SetHTTPCallbacks(hRequest, OnTransferComplete) || !SteamWorks_SendHTTPRequest(hRequest))
		{
			delete hRequest;
			LogError("Failed Request (UTIL_RemoveBan: %s)", szBanID);
		}
	}
	else
	{
		LogError("Failed CreateHTTPRequest (UTIL_RemoveBan: %s)", szBanID);
	}
}

public void OnClientPutInServer(int iClient)
{
	UTIL_SearchBan(iClient);
}

void UTIL_SearchBan(int iClient)
{
	char szAuth[32];
	if(GetClientAuthId(iClient, AuthId_SteamID64, szAuth, sizeof(szAuth)))
	{
		DebugMessage("UTIL_SearchBan -> szAuth: %s, iClient: %i", szAuth, iClient)
		char szBuffer[256];
		FormatEx(szBuffer, sizeof(szBuffer), "http://%s/api/bans/search/0", g_szHost);

		Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, szBuffer);
		if (hRequest)
		{
			SteamWorks_SetHTTPRequestContextValue(hRequest, UID(iClient));
			SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Accept", "application/json");

			if(g_szAuthorizationHash[0])
			{
				SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Authorization", g_szAuthorizationHash);
			}

			szBuffer[0] = 0;

			char szIp[24];
			GetClientIP(iClient, szIp, sizeof(szIp));
			FormatEx(szBuffer, sizeof(szBuffer), "pid=%s&ip=%s", szAuth, szIp);

			if(g_bCheckServerID)
			{
				Format(szBuffer, sizeof(szBuffer), "%s&serverid=%i", szBuffer, g_iServerID);
			}

			DebugMessage("UTIL_SearchBan: %s", szBuffer)

			SteamWorks_SetHTTPRequestRawPostBody(hRequest, "application/x-www-form-urlencoded", szBuffer, strlen(szBuffer)+4);

			if (!SteamWorks_SetHTTPCallbacks(hRequest, OnTransferComplete) || !SteamWorks_SendHTTPRequest(hRequest))
			{
				delete hRequest;
				LogError("Failed Request (UTIL_SearchBan: %s)", szAuth);
			}
		}
		else
		{
			LogError("Failed CreateHTTPRequest (UTIL_SearchBan: %s)", szAuth);
		}
	}
}

public int OnTransferComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any iClient)
{
	DebugMessage("OnTransferComplete: bFailure: %b, bRequestSuccessful: %b, eStatusCode: %i", bFailure, bRequestSuccessful, eStatusCode)
	if (!bFailure && bRequestSuccessful)
	{
		SteamWorks_GetHTTPResponseBodyCallback(hRequest, APIWebResponse, iClient);
	}

	delete hRequest;
}

public int APIWebResponse(const char[] sData, any UserID)
{
	DebugMessage("APIWebResponse: '%s'", sData)
	Handle hJson = json_load(sData);
	if(hJson != null)
	{
		#if DEBUG_MODE
		char szJSON[4096];
		json_dump(hJson, szJSON, sizeof(szJSON), 0);
		DebugMessage("szJSON (hJson): %s", szJSON)
		#endif

		int iClient;
		if(UserID)
		{
			iClient = CID(UserID);
			if(!iClient)
			{
				return;
			}
		}
		else
		{
			iClient = UserID;
		}

		char szMessage[128];
		json_object_get_string(hJson, "message", szMessage, sizeof(szMessage));
		bool bStatus = json_object_get_bool(hJson, "status");
		
		DebugMessage("message: %s", szMessage)
		DebugMessage("status: %b", bStatus)

		if(strcmp(szMessage, "No matches") == 0)	// Не нашли игрока
		{
			return;
		}

		if(bStatus && strcmp(szMessage, "Entries found") == 0)	// Нашли игрока
		{
			Handle hBan = json_object_get(hJson, "bans"); 
			if (hBan != null && json_array_size(hBan))
			{
				Handle hElement = json_array_get(hBan, 0), hObject;
				char szBanID[16];
				json_object_get_string_ex(hElement, hObject, "bid", szBanID, sizeof(szBanID));
				
				int iBannedOn, iDuration;
				
				iBannedOn = json_object_get_int_ex(hElement, hObject, "banned_on");
				iDuration = json_object_get_int_ex(hElement, hObject, "duration");

				if(iDuration == 0 || iBannedOn+iDuration > GetTime())
				{
					char szBanReason[256], szBannedByName[MAX_NAME_LENGTH];
					int iSteamId64 = json_object_get_int_ex(hElement, hObject, "steamid64");
					
					json_object_get_string_ex(hElement, hObject, "ban_reason", szBanReason, sizeof(szBanReason));
					json_object_get_string_ex(hElement, hObject, "banned_by_name", szBannedByName, sizeof(szBannedByName));

					PrintToConsole(iClient, "####################################################################");
					PrintToConsole(iClient, "####################################################################");
					PrintToConsole(iClient, "####################################################################");
					
					PrintToConsole(iClient, "###\t \t Вы забанены на этом сервере");
					PrintToConsole(iClient, "###\t \t Ваш SteamID64: %i", iSteamId64);
					PrintToConsole(iClient, "###\t \t ID Бана: %s", szBanID);
					PrintToConsole(iClient, "###\t \t Забанен админом: %s", szBannedByName);
					PrintToConsole(iClient, "###\t \t Причина: %s", szBanReason);
					
					char szBanTime[64], szDuration[64];
					FormatTime(szBanTime, sizeof(szBanTime), "%d/%m/%Y-%H:%M:%S", iBannedOn);
					PrintToConsole(iClient, "###\t \t Бан выдан: %s", szBanTime);
					
					if(!GetDuration(iDuration, szDuration, sizeof(szDuration)))
					{
						FormatEx(szDuration, sizeof(szDuration), "%i мин.", iDuration/60);
					}

					PrintToConsole(iClient, "###\t \t Длительность: %s", szDuration);

					PrintToConsole(iClient, "###\t \t Подробнее: %s", g_szBanURL);

					PrintToConsole(iClient, "####################################################################");
					PrintToConsole(iClient, "####################################################################");
					PrintToConsole(iClient, "####################################################################");
					
					char szBuffer[512];
					FormatEx(szBuffer, sizeof(szBuffer), "ID Бана: %s\n\
											Забанен админом: %s\n\
											Причина: %s\n\
											Бан выдан: %s\n\
											Длительность: %s\n\
											Подробнее: %s",
					szBanID,
					szBannedByName,
					szBanReason,
					szBanTime,
					szDuration,
					g_szBanURL);
					
					DataPack pack;
					CreateDataTimer(0.2, Timer_KickDelay, pack);
					pack.WriteCell(UID(iClient));
					pack.WriteString(szBuffer);
				}

				delete hElement;
			}
		}
		else
		{
			if(bStatus)
			{
				if(strcmp(szMessage, "Ban added") == 0)
				{
					Handle hBanInfo = json_object_get(hJson, "baninfo");
					DebugMessage("json_typeof (hBanInfo): %i", json_typeof(hBanInfo))
					if (hBanInfo != null)
					{
						//	Handle hElement = json_array_get(hBanInfo, 0);
						char szBanID[16];
						json_object_get_string(hBanInfo, "bid", szBanID, sizeof(szBanID));
						if(iClient)
						{
							int iTarget = GetClientOfUserId(g_iBanTarget[iClient]);
						
							if(iTarget)
							{
								UTIL_SearchBan(iTarget);
							}
							
							PrintToChat(iClient, "Бан успешно добавлен (BanID: %s)", szBanID);
						}
						else
						{
							PrintToServer("Бан успешно добавлен (BanID: %s)", szBanID);
							
							for(int i = 1; i <= MaxClients; ++i)
							{
								if(IsClientInGame(i) && !IsFakeClient(i))
								{
									UTIL_SearchBan(i);
								}
							}
						}

						//	delete hElement;
					}
				}
				
				/*
				if(strcmp(szMessage, "Entry deleted") == 0)
				{
					if(iClient)
					{
						PrintToChat(iClient, "Бан успешно удален (BanID: %s)", g_szFindValue[iClient]);
					}
				}
				*/
			}
			else
			{
				if(iClient)
				{
					PrintToChat(iClient, "Произошла ошибка: %s", szMessage);
				}
				else
				{
					PrintToServer("Произошла ошибка: %s", szMessage);
				}
			}
		}
	}

	delete hJson;
}

//public Action Timer_KickDelay(Handle hTimer, Handle hDataPack)
public Action Timer_KickDelay(Handle hTimer, Handle hDataPack)
{
	ResetPack(hDataPack);
	int iClient = CID(ReadPackCell(hDataPack));
	if(iClient)
	{
		char szMessage[512];
		ReadPackString(hDataPack, szMessage, sizeof(szMessage));
		KickClient(iClient, szMessage);
	}

//	return Plugin_Stop;
}

bool GetDuration(int iDuration, char[] szBuffer, int iMaxLen)
{
	g_hKeyValues.Rewind();
	if(g_hKeyValues.JumpToKey("ban_times"))
	{
		char szKey[64];
		IntToString(iDuration, szKey, sizeof(szKey));
		g_hKeyValues.GetString(szKey, szBuffer, iMaxLen);
		if(szBuffer[0])
		{
			return true;
		}
	}

	return false;
}

void json_object_get_string_ex(Handle &hElement, Handle &hObject, const char[] sKey, char[] szBuffer, int iMaxlength)
{
	hObject = json_object_get(hElement, sKey);
	if(hObject != null)
	{
		if(json_typeof(hObject) == JSON_STRING)
		{
			json_string_value(hObject, szBuffer, iMaxlength);
		}
	}

	delete hObject;
}

int json_object_get_int_ex(Handle &hElement, Handle &hObject, const char[] sKey)
{
	hObject = json_object_get(hElement, sKey);

	int iResult;
	if(hObject != null)
	{
		if(json_is_integer(hObject))
		{
			iResult = json_integer_value(hObject);
		}
	}

	delete hObject;
	return iResult;
}

