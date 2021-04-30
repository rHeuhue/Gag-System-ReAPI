#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <regex>
#include <nvault>

#define CC_COLORS_TYPE CC_COLORS_SHORT
#include <cromchat>

#define LOG_GAGS

#define IP_PATTERN "([0-9]+.*[1-9][0-9]+.*[0-9]+.*[0-9])"
#define VERSION "1.3-ReAPI"

#if !defined MAX_PLAYERS
	#define MAX_PLAYERS 32
#endif

#if !defined MAX_NAME_LENGTH
	#define MAX_NAME_LENGTH 32
#endif

#if !defined MAX_IP_LENGTH
	#define MAX_IP_LENGTH 16
#endif

#if !defined MAX_FMT_LENGTH
	#define MAX_FMT_LENGTH 256
#endif

#if !defined MAX_MENU_LENGTH
	#define MAX_MENU_LENGTH 512
#endif

#define MAX_REASON_LENGHT 64

enum _:GagState
{
	GAG_NOT,
	GAG_YES,
	GAG_EXPIRED
};

new const g_szVaultName[] = "gagsystem";
new const g_szChatPrefix[] = "!g[GagSystem]!n";
new const g_szGagSound[] = "buttons/blip1.wav";
#if defined LOG_GAGS
new const g_szLogFile[] = "addons/amxmodx/logs/gag_system.log";
#endif

new g_iNVaultHandle, Regex:g_iRegexIPPattern, g_iUnused, g_iThinkingEnt;
new g_iUserTarget[MAX_PLAYERS + 1], bool:g_blIsUserMuted[MAX_PLAYERS + 1];
new gp_blHudEnabled, gp_blEnableGagExpireMsg;
new g_GagForward, g_UngagForward;

new g_iMenuPosition[MAX_PLAYERS + 1],
	g_iMenuPlayers[MAX_PLAYERS + 1][MAX_PLAYERS],
	g_iMenuPlayersNum[MAX_PLAYERS + 1],
	g_iMenuOption[MAX_PLAYERS + 1],
	g_iMenuSettings[MAX_PLAYERS + 1],
	g_iMenuReasonOption[MAX_PLAYERS + 1],
	g_iMenuSettingsReason[MAX_PLAYERS + 1][MAX_REASON_LENGHT]

new Array:g_aGagTimes,
	Array:g_aGagReason,
	g_iGagTime


public plugin_init()
{
	register_plugin("Gag System", VERSION, "TheRedShoko @ AMXX-BG.info");
	register_cvar("gagsystem_shoko", VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED);

	register_clcmd("say", "CommandSayExecuted");
	register_clcmd("say_team", "CommandSayExecuted");

	g_GagForward = CreateMultiForward("user_gagged", ET_IGNORE, FP_CELL);
	g_UngagForward = CreateMultiForward("user_ungagged", ET_IGNORE, FP_CELL);

	gp_blHudEnabled = register_cvar("gagsystem_showhud", "1");
	gp_blEnableGagExpireMsg = register_cvar("gagsystem_printexpired", "1");

	#if AMXX_VERSION_NUM >= 183
	hook_cvar_change(gp_blEnableGagExpireMsg, "GagExpireCvarChanged");
	#endif

	RegisterHookChain(RG_CSGameRules_CanPlayerHearPlayer, "RG__CSGameRules_CanPlayerHearPlayer")
	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "RG__CBasePlayer_SetClientUserInfoName")

	register_clcmd("amx_gag", "CommandGag", ADMIN_SLAY, "<name | #id | ip> <time> <reason>");
	register_clcmd("amx_ungag", "CommandUngag", ADMIN_SLAY, "<name | #id | ip>");
	register_clcmd("amx_gagmenu", "cmdGagMenu", ADMIN_SLAY, "- displays gag/ungag menu");
	register_clcmd("amx_TYPE_GAGREASON", "CommandGagReason", ADMIN_SLAY);
	register_clcmd("amx_cleangags", "CommandCleanDB", ADMIN_RCON);

	register_menucmd(register_menuid("Gag Menu"), 1023, "actionGagMenu")

	#if AMXX_VERSION_NUM < 183
	g_iRegexIPPattern = regex_compile(IP_PATTERN, g_iUnused, "", 0);
	#else
	g_iRegexIPPattern = regex_compile_ex(IP_PATTERN);
	#endif

	g_iNVaultHandle = nvault_open(g_szVaultName);

	if (g_iNVaultHandle == INVALID_HANDLE)
	{
		set_fail_state("Failed to open NVault DB!");
	}
	
	g_aGagTimes = ArrayCreate()
	ArrayPushCell(g_aGagTimes, 0)
	ArrayPushCell(g_aGagTimes, 5)
	ArrayPushCell(g_aGagTimes, 10)
	ArrayPushCell(g_aGagTimes, 30)
	ArrayPushCell(g_aGagTimes, 60)
	ArrayPushCell(g_aGagTimes, 1440)
	ArrayPushCell(g_aGagTimes, 10080)
	
	register_srvcmd("amx_menu_gag_times", "amx_menu_setgagtimes")
	
	g_aGagReason = ArrayCreate(64, 1)
	ArrayPushString(g_aGagReason, "Custom Reason")
	ArrayPushString(g_aGagReason, "Flame")
	ArrayPushString(g_aGagReason, "Swearing")
	ArrayPushString(g_aGagReason, "Lame")
	ArrayPushString(g_aGagReason, "Offensive Language")
	ArrayPushString(g_aGagReason, "Spam In Chat")
	
	register_srvcmd("amx_menu_gag_reasons", "amx_menu_setgagreasons")

	g_iThinkingEnt = rg_create_entity("info_target")
	set_entvar(g_iThinkingEnt, var_nextthink, get_gametime() + 0.1)
	SetThink(g_iThinkingEnt, "RG__Entity_Think")

	CC_SetPrefix(g_szChatPrefix)
}

public plugin_precache()
{
	precache_sound(g_szGagSound);
}

public plugin_end()
{
	nvault_close(g_iNVaultHandle);
	regex_free(g_iRegexIPPattern);
}

public plugin_natives()
{
	register_native("is_user_gagged", "native_is_gagged");

	register_native("gag_user", "native_gag_user");
	register_native("gag_user_byid", "native_gag_id");

	register_native("ungag_user", "native_ungag_user");
	register_native("ungag_user_byid", "native_ungag_id");
}

public native_is_gagged()
{
	new id = get_param(1);
	new bool:shouldPrint = bool:get_param(2);

	if (!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "Invalid player ID %d", id);
		return false;
	}

	return IsUserGagged(id, shouldPrint) == GAG_YES;
}

public native_gag_user()
{
	new szIP[MAX_IP_LENGTH], szName[MAX_NAME_LENGTH], iDuration, szReason[MAX_REASON_LENGHT], szAdmin[MAX_NAME_LENGTH];

	get_string(1, szName, charsmax(szName));
	get_string(2, szIP, charsmax(szIP));
	iDuration = get_param(3);
	get_string(4, szReason, charsmax(szReason));
	get_string(5, szAdmin, charsmax(szAdmin));

	if (!regex_match_c(szIP, g_iRegexIPPattern, g_iUnused))
	{
		log_error(AMX_ERR_NATIVE, "%s is not a valid IP Address!", szIP);
		return;
	}

	if (iDuration < 0) 
	{
		log_error(AMX_ERR_NATIVE, "Time cannot be negative!");
		return;
	}

	GagUser(szName, szIP, iDuration, szReason, szAdmin);
}

public native_gag_id()
{
	new id;

	id = get_param(1);

	if (!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "Invalid player ID %d", id);
		return;
	}

	new szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szReason[MAX_REASON_LENGHT], iDuration, szAdmin[MAX_NAME_LENGTH];
	iDuration = get_param(2);

	if (iDuration < 0) 
	{
		log_error(AMX_ERR_NATIVE, "Time cannot be negative!");
		return;
	}

	get_string(3, szReason, charsmax(szReason));
	get_string(4, szAdmin, charsmax(szAdmin));

	get_user_name(id, szName, charsmax(szName));
	get_user_ip(id, szIP, charsmax(szIP), 1);

	GagUser(szName, szIP, iDuration, szReason, szAdmin);
}

public native_ungag_user()
{
	new szIP[MAX_IP_LENGTH], szName[MAX_NAME_LENGTH], szAdmin[MAX_NAME_LENGTH];

	get_string(1, szName, charsmax(szName));
	get_string(2, szIP, charsmax(szIP));
	get_string(3, szAdmin, charsmax(szAdmin));

	if (!regex_match_c(szIP, g_iRegexIPPattern, g_iUnused))
	{
		log_error(AMX_ERR_NATIVE, "%s is not a valid IP Address!", szIP);
		return;
	}

	UngagUser(szName, szIP, szAdmin);
}

public native_ungag_id()
{
	new id;

	id = get_param(1);

	if (!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "Invalid player ID %d", id);
		return;
	}

	new szAdmin[MAX_NAME_LENGTH], szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH];

	get_string(2, szAdmin, charsmax(szAdmin));

	get_user_name(id, szName, charsmax(szName));
	get_user_ip(id, szIP, charsmax(szIP), 1);

	UngagUser(szName, szIP, szAdmin);
}

public client_putinserver(id)
{
	g_blIsUserMuted[id] = IsUserGagged(id, false) == GAG_YES;
}

public amx_menu_setgagtimes()
{
	new szBuffer[32]
	new szArgs = read_argc()
	
	if (szArgs <= 1)
	{
		server_print("usage: amx_menu_gag_times <time1> [time2] [time3] ...")
		server_print("   use time of 0 for permanent.")
		return
	}
	
	ArrayClear(g_aGagTimes)
	
	for (new i = 1; i < szArgs; i++)
	{
		read_argv(i, szBuffer, charsmax(szBuffer))
		ArrayPushCell(g_aGagTimes, str_to_num(szBuffer))
	}
}
public amx_menu_setgagreasons()
{
	new szBuffer[MAX_REASON_LENGHT]
	new szArgs = read_argc()
	
	if (szArgs <= 1)
	{
		server_print("usage: amx_menu_gag_reasons <reason1> [reason2] [reason3] ...")
		server_print("   use reason of ^"Custom Reason^" for using custom reason.")
		return
	}
	
	ArrayClear(g_aGagReason)
	
	for (new i = 1;  i < szArgs; i++)
	{
		read_argv(i, szBuffer, charsmax(szBuffer))
		ArrayPushString(g_aGagReason, szBuffer)
	}
	
}

#if AMXX_VERSION_NUM >= 183
public GagExpireCvarChanged(pcvar, szOldValue[], szNewValue[])
{
	if (str_to_num(szNewValue) == 1)
	{
		set_entvar(g_iThinkingEnt, var_nextthink, get_gametime() + 1.0);
	}
}
#endif

public RG__CSGameRules_CanPlayerHearPlayer(iReceiver, iSender)
{
	if (iReceiver == iSender || !is_user_connected(iSender))
	{
		return HC_CONTINUE;
	}

	if (g_blIsUserMuted[iSender])
	{
		SetHookChainReturn(ATYPE_BOOL, false);
		return HC_SUPERCEDE;
	}

	return HC_CONTINUE;
}

public RG__CBasePlayer_SetClientUserInfoName(id, szInfoBuffer[], szNewName[])
{
	if (IsUserGagged(id, false) == GAG_YES)
	{
		SetHookChainReturn(ATYPE_INTEGER, false);
		return HC_SUPERCEDE;
	}
	return HC_CONTINUE;
}

public RG__Entity_Think(iEnt)
{
	if (iEnt != g_iThinkingEnt || !get_pcvar_num(gp_blEnableGagExpireMsg))
	{
		return;
	}

	static iPlayers[MAX_PLAYERS], iPlayersNum, id;
	get_players(iPlayers, iPlayersNum);

	for (--iPlayersNum; iPlayersNum >= 0; iPlayersNum--)
	{
		id = iPlayers[iPlayersNum]

		if (IsUserGagged(id, false) == GAG_EXPIRED)
		{
			static szName[MAX_NAME_LENGTH]
			get_user_name(id, szName, charsmax(szName))

			CC_SendMessage(0, "Player !t%s !nis no longer gagged!", szName)

			if (get_pcvar_num(gp_blHudEnabled))
			{
				static szHudMessage[MAX_FMT_LENGTH]
				formatex(szHudMessage, charsmax(szHudMessage), "%s gag has expired", szName)
				send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0)
			}
		}
	}

	set_entvar(iEnt, var_nextthink, get_gametime() + 1.0);
}

public CommandSayExecuted(id)
{
	if (IsUserGagged(id) == GAG_YES)
	{
		return PLUGIN_HANDLED;
	}

	return PLUGIN_CONTINUE;
}

public CommandGag(id, iLevel, iCmdId)
{
	if (!cmd_access(id, iLevel, iCmdId, 4))
	{
		return PLUGIN_HANDLED;
	}

	new szTarget[MAX_PLAYERS], szTargetIP[MAX_IP_LENGTH], szTime[8], szReason[MAX_REASON_LENGHT];
	read_argv(1, szTarget, charsmax(szTarget));

	if (!regex_match_c(szTarget, g_iRegexIPPattern, g_iUnused))
	{
		new iTarget = cmd_target(id, szTarget);

		if (!iTarget)
		{
			return PLUGIN_HANDLED;
		}

		get_user_name(iTarget, szTarget, charsmax(szTarget));
		get_user_ip(iTarget, szTargetIP, charsmax(szTargetIP), 1);
		g_blIsUserMuted[iTarget] = true;
	}
	else
	{
		copy(szTargetIP, charsmax(szTargetIP), szTarget);
	}

	read_argv(2, szTime, charsmax(szTime));
	read_argv(3, szReason, charsmax(szReason));
	new iTime = str_to_num(szTime);

	new szAdmin[MAX_NAME_LENGTH];
	get_user_name(id, szAdmin, charsmax(szAdmin));

	console_print(id, "%s", GagUser(szTarget, szTargetIP, iTime, szReason, szAdmin));

	return PLUGIN_HANDLED;
}

public CommandUngag(id, iLevel, iCmdId)
{
	if (!cmd_access(id, iLevel, iCmdId, 2))
	{
		return PLUGIN_HANDLED;
	}

	new szTarget[MAX_PLAYERS], szTargetIP[MAX_IP_LENGTH];
	read_argv(1, szTarget, charsmax(szTarget));

	if (!regex_match_c(szTarget, g_iRegexIPPattern, g_iUnused))
	{
		new iTarget = cmd_target(id, szTarget, CMDTARGET_ALLOW_SELF);

		if (!iTarget)
		{
			return PLUGIN_HANDLED;
		}

		get_user_name(iTarget, szTarget, charsmax(szTarget));
		get_user_ip(iTarget, szTargetIP, charsmax(szTargetIP), 1);
	}
	else
	{
		copy(szTargetIP, charsmax(szTargetIP), szTarget);
	}

	new szAdminName[MAX_NAME_LENGTH];
	get_user_name(id, szAdminName, charsmax(szAdminName));

	console_print(id, "%s", UngagUser(szTarget, szTargetIP, szAdminName));

	return PLUGIN_HANDLED;
}

public actionGagMenu(id, iKey)
{
	switch (iKey)
	{
		case 6:
		{
			new szReasons[MAX_REASON_LENGHT]
			
			++g_iMenuReasonOption[id]
			g_iMenuReasonOption[id] %= ArraySize(g_aGagReason)
			
			ArrayGetString(g_aGagReason, g_iMenuReasonOption[id], szReasons, charsmax(szReasons))
			copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), szReasons)
			
			displayGagMenu(id, g_iMenuPosition[id])
		}
		case 7:
		{
			++g_iMenuOption[id]
			g_iMenuOption[id] %= ArraySize(g_aGagTimes)
			
			g_iMenuSettings[id] = ArrayGetCell(g_aGagTimes, g_iMenuOption[id])
			
			displayGagMenu(id, g_iMenuPosition[id])
		}
		case 8:
		{
			displayGagMenu(id, ++g_iMenuPosition[id])
		}
		case 9:
		{
			displayGagMenu(id, --g_iMenuPosition[id])
		}
		default:
		{
			g_iGagTime = g_iMenuSettings[id]
			
			new szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szAdminName[MAX_NAME_LENGTH]
			g_iUserTarget[id] = g_iMenuPlayers[id][g_iMenuPosition[id] * 6 + iKey]

			if (/*~get_user_flags(id) & (ADMIN_KICK | ADMIN_RCON) && g_iGagTime <= 0
				|| */~get_user_flags(id) & (ADMIN_KICK | ADMIN_RCON) && g_iGagTime <= 0 && IsUserGagged(g_iUserTarget[id], false) == GAG_NOT)
			{
				client_print(id, print_center, "You have no access to that command!")
				displayGagMenu(id, g_iMenuPosition[id])
				return PLUGIN_HANDLED
			}

			if (get_user_flags(g_iUserTarget[id]) & ADMIN_IMMUNITY && !(get_user_flags(id) & ADMIN_RCON) && IsUserGagged(g_iUserTarget[id], false) == GAG_NOT
				|| get_user_flags(g_iUserTarget[id]) & (ADMIN_IMMUNITY & ADMIN_RCON))
			{
				client_print(id, print_center, "You can't gag this user due to his/her immunity..")
				displayGagMenu(id, g_iMenuPosition[id])
				return PLUGIN_HANDLED
			}

			get_user_name(id, szAdminName, charsmax(szAdminName))
			get_user_name(g_iUserTarget[id], szName, charsmax(szName))
			get_user_ip(g_iUserTarget[id], szIP, charsmax(szIP), 1)
			
			if (IsUserGagged(g_iUserTarget[id], false) == GAG_YES)
			{
				UngagUser(szName, szIP, szAdminName)
				displayGagMenu(id, g_iMenuPosition[id])
			}
			else
			{
				if (equal(g_iMenuSettingsReason[id], "Custom Reason") || g_iMenuSettingsReason[id][0] == EOS)
				{
					client_cmd(id, "messagemode amx_TYPE_GAGREASON")
					CC_SendMessage(id, "Type in the !treason!n, or !g!cancel !nto cancel.")
				}
				else
				{
					GagUser(szName, szIP, g_iGagTime, g_iMenuSettingsReason[id], szAdminName)
					g_blIsUserMuted[g_iUserTarget[id]] = true
				}
			}
		}
	}
	return PLUGIN_HANDLED
}

displayGagMenu(id, iPos)
{
	if (iPos < 0)
	{
		return
	}
	
	get_players(g_iMenuPlayers[id], g_iMenuPlayersNum[id])

	new szMenu[MAX_MENU_LENGTH], i, szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH]
	new b = 0 
	new iStart = iPos * 6
	
	if (iStart >= g_iMenuPlayersNum[id])
	{
		iStart = iPos = g_iMenuPosition[id] = 0
	}
	
	new iLen = formatex(szMenu, charsmax(szMenu), "\wGag\d/\yUngag \rMenu\R%d/%d^n\w^n", iPos + 1, (g_iMenuPlayersNum[id] / 6 + ((g_iMenuPlayersNum[id] % 6) ? 1 : 0)))
	new iEnd = iStart + 6
	new iKeys = MENU_KEY_0|MENU_KEY_7|MENU_KEY_8
	
	if (iEnd > g_iMenuPlayersNum[id])
	{
		iEnd = g_iMenuPlayersNum[id]
	}
	
	for (new a = iStart; a < iEnd; ++a)
	{
		i = g_iMenuPlayers[id][a]
		get_user_name(i, szName, charsmax(szName))
		get_user_ip(i, szIP, charsmax(szIP), 1)
		
		if (is_user_bot(i) || (access(i, ADMIN_IMMUNITY) && i != id))
		{
			++b
			
			if (get_user_flags(i) & ADMIN_IMMUNITY)
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d%i. %s \r[\wHas immunity\r]^n\w", b, szName)
			else
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d%i. %s^n\w", b, szName)
		}
		else
		{
			iKeys |= (1<<b)

			if (is_user_admin(i))
			{
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%i. %s%s \r* %s^n\w", ++b, IsUserGagged(i, false) ? "\y" : "\w", szName, GetGaggedPlayerInfo(szIP))
			}
			else
			{
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "%i. %s%s %s^n\w", ++b, IsUserGagged(i, false) ? "\y" : "\w", szName, GetGaggedPlayerInfo(szIP))
			}
		}
	}
	
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "^n7. Gag reason: %s%s\w", equal(g_iMenuSettingsReason[id], "Custom Reason") ? "\r" : "\y", g_iMenuSettingsReason[id])
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, g_iMenuSettings[id] ? "^n8. Gag for \y%i minutes\w^n" : "^n8. Gag \rpermanently\w^n", g_iMenuSettings[id])
	
	if (iEnd != g_iMenuPlayersNum[id])
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "^n9. More...^n0. %s", iPos ? "Back" : "Exit")
		iKeys |= MENU_KEY_9
	}
	else
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "^n0. %s", iPos ? "Back" : "Exit");
	}

	show_menu(id, iKeys, szMenu, -1, "Gag Menu")
}

public CommandGagReason(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1) || !is_user_connected(g_iUserTarget[id]))
		return PLUGIN_HANDLED
	
	new szReason[MAX_REASON_LENGHT], szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szAdminName[MAX_NAME_LENGTH]
	read_argv(1, szReason, charsmax(szReason))
	
	if (equali(szReason, "!cancel"))
	{
		displayGagMenu(id, g_iMenuPosition[id])
		return PLUGIN_HANDLED
	}

	get_user_name(id, szAdminName, charsmax(szAdminName))
	get_user_name(g_iUserTarget[id], szName, charsmax(szName))
	get_user_ip(g_iUserTarget[id], szIP, charsmax(szIP), 1)

	GagUser(szName, szIP, g_iGagTime, szReason, szAdminName)
	g_blIsUserMuted[g_iUserTarget[id]] = true
	return PLUGIN_HANDLED
}

public cmdGagMenu(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	g_iMenuOption[id] = 0
	g_iMenuReasonOption[id] = 0
	g_iUserTarget[id] = 0

	if (ArraySize(g_aGagTimes) > 0)
	{
		g_iMenuSettings[id] = ArrayGetCell(g_aGagTimes, g_iMenuOption[id])
	}
	else
	{
		// should never happen, but failsafe
		g_iMenuSettings[id] = 0
	}
	
	if (ArraySize(g_aGagReason) > 0)
	{
		new szReasons[MAX_REASON_LENGHT]
			
		ArrayGetString(g_aGagReason, g_iMenuReasonOption[id], szReasons, charsmax(szReasons))
		copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), szReasons)
	}
	else
	{
		// should never happen, but failsafe
		copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), "Custom Reason")
	}
	displayGagMenu(id, g_iMenuPosition[id] = 0)

	return PLUGIN_HANDLED
}

public CommandCleanDB(id, iLevel, iCmdId)
{
	if (!cmd_access(id, iLevel, iCmdId, 1))
	{
		return PLUGIN_HANDLED;
	}

	nvault_prune(g_iNVaultHandle, 0, get_systime());

	console_print(id, "Database has been cleaned.");

	return PLUGIN_HANDLED;
}

UngagUser(szName[], szIP[], szAdmin[])
{
	new szResult[64], szTemp[3];

	if (!nvault_get(g_iNVaultHandle, szIP, szTemp, charsmax(szTemp)))
	{
		formatex(szResult, charsmax(szResult), "User with IP %s not found.", szIP);
		return szResult;
	}

	nvault_remove(g_iNVaultHandle, szIP);

	if (!equal(szName, szIP))
	{
		new iTarget = cmd_target(0, szName, 0);

		g_blIsUserMuted[iTarget] = false;

		CC_SendMessage(iTarget, "You have been ungagged by admin !t%s!n!", szAdmin)

		CC_SendMessage(0, "Player !t%s !nhas been ungagged by !g%s!n.", szName, szAdmin)

		if (get_pcvar_num(gp_blHudEnabled))
		{
			new szHudMessage[MAX_FMT_LENGTH]
			formatex(szHudMessage, charsmax(szHudMessage), "%s has been ungagged by %s", szName, szAdmin)
			send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0)
		}
	}

	new id = find_player("d", szIP);
	if (id != 0)
	{
		ExecuteForward(g_UngagForward, g_iUnused, id);
	}

	#if defined LOG_GAGS
	log_to_file(g_szLogFile, "[UNGAG] ADMIN: %s | TARGET_NAME: %s [IP: %s]", szAdmin, szName, szIP);
	#endif
	copy(szResult, charsmax(szResult), "Player has been ungagged");
	return szResult;
}

GagUser(szName[], szIP[], iDuration, szReason[], szAdminName[])
{
	new iExpireTime = iDuration != 0 ? get_systime() + (iDuration * 60) : 0;

	new szResult[64];

	if (nvault_get(g_iNVaultHandle, szIP, szResult, charsmax(szResult)))
	{
		copy(szResult, charsmax(szResult), "Player is already gagged.");
		return szResult;
	}

	new szValue[512];
	formatex(szValue, charsmax(szValue), "^"%s^"#^"%s^"#%d#^"%s^"", szName, szReason, iExpireTime, szAdminName);

	if (iExpireTime == 0)
	{
		CC_SendMessage(0, "Player!t %s!n has been gagged by!g %s!n. Reason: !t%s!n. Gag expires!t never!n.", szName, szAdminName, szReason);

		if (get_pcvar_num(gp_blHudEnabled))
		{
			new szHudMessage[MAX_FMT_LENGTH]
			formatex(szHudMessage, charsmax(szHudMessage), "%s has been gagged by %s^nExpires: Never^nReason: %s", szName, szAdminName, szReason)
			send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0)
		}
	}
	else
	{
		CC_SendMessage(0, "Player!t %s!n has been gagged by!g %s!n. Reason: !t%s!n. Gag expires!t %s", szName, szAdminName, szReason, GetTimeAsString(iDuration * 60));

		if (get_pcvar_num(gp_blHudEnabled))
		{
			new szHudMessage[MAX_FMT_LENGTH]
			formatex(szHudMessage, charsmax(szHudMessage), "%s has been gagged by %s^nExpires in %s^nReason: %s", szName, szAdminName, GetTimeAsString(iDuration * 60), szReason)
			send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0)
		}
	}
	
	emit_sound(0, CHAN_AUTO, g_szGagSound, 1.0, ATTN_NORM, SND_SPAWNING, PITCH_NORM);
	

	#if defined LOG_GAGS
	log_to_file(g_szLogFile, "ADMIN: %s | PLAYER: %s [IP: %s] | REASON: %s | TIME: %s", szAdminName, szName, szIP, szReason, GetTimeAsString(iDuration * 60));
	#endif
	

	new id = find_player("d", szIP);

	if (id != 0)
	{
		ExecuteForward(g_GagForward, g_iUnused, id);
	}
	
	nvault_set(g_iNVaultHandle, szIP, szValue);
	
	copy(szResult, charsmax(szResult), "Player successfully gagged.");
	return szResult;
}

IsUserGagged(id, bool:print = true)
{
	new szIP[MAX_IP_LENGTH], szVaultData[512];
	get_user_ip(id, szIP, charsmax(szIP), 1);

	if (!nvault_get(g_iNVaultHandle, szIP, szVaultData, charsmax(szVaultData)))
	{
		g_blIsUserMuted[id] = false;
		return GAG_NOT;
	}

	new szGaggedName[MAX_NAME_LENGTH], szReason[MAX_REASON_LENGHT], szExpireDate[32], szAdminName[MAX_NAME_LENGTH];
	replace_all(szVaultData, charsmax(szVaultData), "#", " ");
	parse(szVaultData, szGaggedName, charsmax(szGaggedName), szReason, charsmax(szReason), szExpireDate, charsmax(szExpireDate), szAdminName, charsmax(szAdminName));

	new iExpireTime = str_to_num(szExpireDate);

	if (get_systime() < iExpireTime || iExpireTime == 0)
	{
		if (print)
		{
			if (iExpireTime == 0)
			{
				CC_SendMessage(id, "You are gagged! Your gag expires!t never!n.");
			}
			else
			{
				CC_SendMessage(id, "You are gagged! Your gag expires in!t %s", GetTimeAsString(iExpireTime - get_systime()));
			}

			CC_SendMessage(id, "Gagged by!g %s!n. Gagged nickname:!t %s!n. Gag reason:!t %s!n.", szAdminName, szGaggedName, szReason);
		}

		g_blIsUserMuted[id] = true;

		return GAG_YES;
	}

	g_blIsUserMuted[id] = false;
	ExecuteForward(g_UngagForward, g_iUnused, id);

	nvault_remove(g_iNVaultHandle, szIP);

	return GAG_EXPIRED;
}

stock GetGaggedPlayerInfo(const iPlayerIP[])
{
	new szGaggedName[MAX_NAME_LENGTH], szReason[MAX_REASON_LENGHT], szExpireDate[32], szAdminName[MAX_NAME_LENGTH], szGagTimeLeft[64], szVaultData[512];

	if (!nvault_get(g_iNVaultHandle, iPlayerIP, szVaultData, charsmax(szVaultData)))
	{
		formatex(szGagTimeLeft, charsmax(szGagTimeLeft), "")
	}
	else
	{
		replace_all(szVaultData, charsmax(szVaultData), "#", " ");
		parse(szVaultData, szGaggedName, charsmax(szGaggedName), szReason, charsmax(szReason), szExpireDate, charsmax(szExpireDate), szAdminName, charsmax(szAdminName));

		new iExpireTime = str_to_num(szExpireDate);

		if (get_systime() < iExpireTime || iExpireTime == 0)
		{
			if (iExpireTime == 0)
				formatex(szGagTimeLeft, charsmax(szGagTimeLeft), "\dExpire: \rNever")
			else
				formatex(szGagTimeLeft, charsmax(szGagTimeLeft), "\dExpire: \r%s", GetTimeAsString(iExpireTime - get_systime()))
		}
	}
	return szGagTimeLeft
}

GetTimeAsString(seconds)
{
	new iYears = seconds / 31536000;
	seconds %= 31536000;

	new iMonths = seconds / 2592000;
	seconds %= 2592000;

	new iWeeks = seconds / 604800;
	seconds %= 604800;

	new iDays = seconds / 86400;
	seconds %= 86400;

	new iHours = seconds / 3600;
	seconds %= 3600;

	new iMinutes = seconds / 60;
	seconds %= 60;

	new szResult[256];

	if (iYears)
	{
		format(szResult, charsmax(szResult), "%s%d Year%s ", szResult, iYears, iYears == 1 ? "" : "s");
	}

	if (iMonths)
	{
		format(szResult, charsmax(szResult), "%s%d Month%s ", szResult, iMonths, iMonths == 1 ? "" : "s");
	}

	if (iWeeks)
	{
		format(szResult, charsmax(szResult), "%s%d Week%s ", szResult, iWeeks, iWeeks == 1 ? "" : "s");
	}

	if (iDays)
	{
		format(szResult, charsmax(szResult), "%s%d Day%s ", szResult, iDays, iDays == 1 ? "" : "s");
	}

	if (iHours)
	{
		format(szResult, charsmax(szResult), "%s%d Hour%s ", szResult, iHours, iHours == 1 ? "" : "s");
	}

	if (iMinutes)
	{
		format(szResult, charsmax(szResult), "%s%d Minute%s ", szResult, iMinutes, iMinutes == 1 ? "" : "s");
	}

	if (seconds)
	{
		format(szResult, charsmax(szResult), "%s%d Second%s", szResult, seconds, seconds == 1 ? "" : "s");
	}

	return szResult;
}

/*
* id
* Player to send the message to.
*   0 = everyone
* 
* text[]
*   Text to send.
* 
* Float:X
*   X position on screen.
* 
* Float:Y
*   Y position on screen.
* 
* R
*   Red color.
* 
* G
*   Green color.
* 
* B
*   Blue color.
* 
* A
*   Alpha.
*   Default value: 255
* 
* Float:holdtime
*   Float:fadeintime
*   Time to fade in message
*   Default value: 0.1
* 
* Float:fadeouttime
*   Time to fade out message
*   Default value: 0.1
* 
* channel
*   Textchannel
*   -1 = auto choose.
*   Default value: -1
* 
* effect
*   Effect of message.
*   1 = Flicker with 2nd color.
*   2 = Print out as 2nd color, fade into 1st color.
*     effecttime decides fade time between colors.
*     fadeintime decides how fast the letters should be printed out.
*   Default value: 0
* 
* effect_R
*   Red color of effect.
*   Default value: 0
* 
* effect_G
*   Green color of effect.
*   Default value: 0
* 
* effect_B
*   Blue color of effect.
*   Default value: 0
* 
* effect_A
*   Alpha of effect.
*   Default value: 255
* 
* Float:effecttime
*   Only for effect 2.
*   Default value: 0.0
*/
stock send_hudmessage(id,text[],Float:X,Float:Y,R,G,B,A=255,Float:holdtime=5.0,Float:fadeintime=0.1,Float:fadeouttime=0.1,channel=-1,effect=0,effect_R=0,effect_G=0,effect_B=0,effect_A=255,Float:effecttime=0.0)
{
	if (id)
		message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, {0,0,0}, id)
	else
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(TE_TEXTMESSAGE)
	write_byte(channel)
	write_short(coord_to_hudmsgshort(X))
	write_short(coord_to_hudmsgshort(Y))
	write_byte(effect)
	write_byte(R)   
	write_byte(G)
	write_byte(B)
	write_byte(A)
	write_byte(effect_R)
	write_byte(effect_G)
	write_byte(effect_B)
	write_byte(effect_A)
	write_short(seconds_to_hudmsgshort(fadeintime))
	write_short(seconds_to_hudmsgshort(fadeouttime))
	write_short(seconds_to_hudmsgshort(holdtime))
	if (effect == 2)
		write_short(seconds_to_hudmsgshort(effecttime))
	write_string(text)
	message_end()
}

/* 0.0 - 255.99609375 seconds */
stock seconds_to_hudmsgshort(Float:sec)
{
	new output = floatround(sec * 256)
	return output < 0 ? 0 : output > 65535 ? 65535 : output
}

stock coord_to_hudmsgshort(Float:coord)
{
	new output = floatround(coord * 8192)
	return output < -32768 ? -32768 : output > 32767 ? 32767 : output
}