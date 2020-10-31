/*  
*    Copyright (C) 2019  LuxLuma		acceliacat@gmail.com
*
*    This program is free software: you can redistribute it and/or modify
*    it under the terms of the GNU General Public License as published by
*    the Free Software Foundation, either version 3 of the License, or
*    (at your option) any later version.
*
*    This program is distributed in the hope that it will be useful,
*    but WITHOUT ANY WARRANTY; without even the implied warranty of
*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*    GNU General Public License for more details.
*
*    You should have received a copy of the GNU General Public License
*    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/


#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <sourcescramble>
#include <smlib>
#include <timocop>
#include <lux_library>
#include <dhooks>

#pragma newdecls required

#define GAMEDATA "Bile_Bomb_rework"
#define PLUGIN_VERSION	"1.0"


#define ENTITY_SAFE_LIMIT 1900

#define ACID_ATTACK_INTERVAL 0.1
#define ACID_DAMAGE_PERCENT 0.0095
#define ACID_ATTACK_INTERVAL_SURVIVOR 0.1
#define ACID_DAMAGE_PERCENT_SURVIVORS 0.01

#define ACID_LIFETIME 0.5 //m_itTimer
#define ACID_LIFETIME_SURVIVOR 0.15 //m_itTimer

#define VOMIT_JAR_LIFETIME_SURVIVOR 20
#define VOMIT_JAR_RADIUS_SURVIVOR 90
#define VOMIT_JAR_RADIUS 200
#define VOMIT_JAR_LIFETIME 20

Handle hOnVomitedUpon;
Handle hOnVomitedUpon_NB;

int g_iEffectIndex = -1;
int g_iVomitJar_ParticleReplacement = INVALID_STRING_INDEX;
int g_iVomitJar_AcidSplash = INVALID_STRING_INDEX;
int g_iVomitJar_AcidTrail = INVALID_STRING_INDEX;
int g_iVomitJar_GooTrail = INVALID_STRING_INDEX;

float g_flAcidAttackTime[2048+1] = {-1.0, ...};
float g_flAcidAttackNextAttack[2048+1] = {-1.0, ...};
int g_iAcidAttackerUserid[2048+1];

float g_flPreventBreakTime[2048+1];


static char g_sRandomSound[6][] =
{
	")player/PZ/hit/zombie_slice_1.wav",
	")player/PZ/hit/zombie_slice_2.wav",
	")player/PZ/hit/zombie_slice_3.wav",
	")player/PZ/hit/zombie_slice_4.wav",
	")player/PZ/hit/zombie_slice_5.wav",
	")player/PZ/hit/zombie_slice_6.wav"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "[L4D2]Bile_Bomb_rework",
	author = "Lux",
	description = "-",
	version = PLUGIN_VERSION,
	url = "https://github.com/LuxLuma"
};

public void OnPluginStart()
{
	Handle hGamedata = LoadGameConfigFile(GAMEDATA);
	if(hGamedata == null) 
		SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);
		
	Handle hDetour;
	hDetour = DHookCreateFromConf(hGamedata, "CVomitJarProjectile::ExplodeVomit");
	if(!hDetour)
		SetFailState("Failed to find 'CVomitJarProjectile::ExplodeVomit' signature");
	
	if(!DHookEnableDetour(hDetour, false, PreExplodeVomit))
		SetFailState("Failed to detour 'CVomitJarProjectile::ExplodeVomit'");
	
	hDetour = DHookCreateFromConf(hGamedata, "CVomitJarProjectile::Detonate");
	if(!hDetour)
		SetFailState("Failed to find 'CVomitJarProjectile::Detonate' signature");
	
	if(!DHookEnableDetour(hDetour, false, PreDetonate))
		SetFailState("Failed to detour 'CVomitJarProjectile::Detonate'");
	
	StartPrepSDKCall(SDKCall_Player);
	if(!PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTerrorPlayer::OnVomitedUpon"))
		SetFailState("Error finding the 'CTerrorPlayer::OnVomitedUpon' signature.");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	
	hOnVomitedUpon = EndPrepSDKCall();
	if(hOnVomitedUpon == null)
		SetFailState("Unable to prep SDKCall 'CTerrorPlayer::OnVomitedUpon'");
	
	StartPrepSDKCall(SDKCall_Entity);
	if(!PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "Infected::OnHitByVomitJar"))
		SetFailState("Error finding the 'Infected::OnHitByVomitJar' signature.");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	
	hOnVomitedUpon_NB = EndPrepSDKCall();
	if(hOnVomitedUpon_NB == null)
		SetFailState("Unable to prep SDKCall 'Infected::OnHitByVomitJar");
	
	delete hGamedata;
	
	HookConVarChange(FindConVar("vomitjar_duration_survivor"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_radius_survivors"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_radius"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_duration_infected_pz"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_duration_infected_bot"), CvarsChanged);
	CvarsChange();
}

public void CvarsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	CvarsChange();
}

void CvarsChange()
{
	char buf[32];
	IntToString(VOMIT_JAR_LIFETIME_SURVIVOR, buf, sizeof(buf));
	SetConVarString(FindConVar("vomitjar_duration_survivor"), buf);
	IntToString(VOMIT_JAR_RADIUS_SURVIVOR, buf, sizeof(buf));
	SetConVarString(FindConVar("vomitjar_radius_survivors"), buf);
	IntToString(VOMIT_JAR_RADIUS, buf, sizeof(buf));
	SetConVarString(FindConVar("vomitjar_radius"), buf);
	IntToString(VOMIT_JAR_LIFETIME, buf, sizeof(buf));
	SetConVarString(FindConVar("vomitjar_duration_infected_pz"), buf);
	SetConVarString(FindConVar("vomitjar_duration_infected_bot"), buf);
}

public void OnMapStart()
{
	g_iEffectIndex = __FindStringIndex2(FindStringTable("EffectDispatch"), "ParticleEffect");
	if(g_iEffectIndex == INVALID_STRING_INDEX)
		SetFailState("Unable to find 'EffectDispatch/ParticleEffect' index");
	
	//Credit smlib
	static int particleEffectNames = INVALID_STRING_TABLE;
	if (particleEffectNames == INVALID_STRING_TABLE) 
	{
		if ((particleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) 
		{
			SetFailState("Unable to find 'ParticleEffectNames' Table index");
		}
	}
	g_iVomitJar_ParticleReplacement = __FindStringIndex2(particleEffectNames, "smoker_smokecloud");
	g_iVomitJar_AcidSplash = PrecacheParticleSystem("spitter_areaofdenial");
	g_iVomitJar_AcidTrail = PrecacheParticleSystem("spitter_areaofdenial_base_refract");
	g_iVomitJar_GooTrail = PrecacheParticleSystem("spitter_slime_trail");
	
	for(int i = 0; i < sizeof(g_sRandomSound); i++)
		PrecacheSound(g_sRandomSound[i], true);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
}

public void PostThinkPost(int client)
{
	int team = GetClientTeam(client);
	if(!IsPlayerAlive(client) || team < 2)
		return;
	
	float fTime = GetGameTime();
	
	if(g_flAcidAttackTime[client] < fTime)
		return;
	
	if(g_flAcidAttackNextAttack[client] > fTime)
		return;
	
	if(team == 2)
	{
		SDKHooks_TakeDamage(client, 0, 0, float(RoundToCeil(GetEntProp(client, Prop_Data, "m_iMaxHealth", 4) * ACID_DAMAGE_PERCENT_SURVIVORS)), DMG_ACID);
		g_flAcidAttackNextAttack[client] = fTime + ACID_ATTACK_INTERVAL_SURVIVOR;
	}
	else if(team == 3)
	{
		SDKHooks_TakeDamage(client, 0, GetClientOfUserId(g_iAcidAttackerUserid[client]), 1.0 + float(RoundToCeil(GetEntProp(client, Prop_Data, "m_iMaxHealth", 4) * ACID_DAMAGE_PERCENT)), DMG_ACID);
		g_flAcidAttackNextAttack[client] = fTime + ACID_ATTACK_INTERVAL;
	}
	AcidOnFloor(client);
	EmitSoundToAll(g_sRandomSound[GetRandomInt(0, 5)], client, SNDCHAN_BODY, SNDLEVEL_CAR, _, SNDVOL_NORMAL);
}

public void AcidThink(int entity)
{
	if(GetEntProp(entity, Prop_Data, "m_iHealth") <= 0)
		return;
	
	float fTime = GetGameTime();
	if(g_flAcidAttackTime[entity] < fTime)
		return;
	
	if(g_flAcidAttackNextAttack[entity] > fTime)
		return;
	
	float flDamage = float(RoundToCeil(GetEntProp(entity, Prop_Data, "m_iMaxHealth", 4) * ACID_DAMAGE_PERCENT));	
	SDKHooks_TakeDamage(entity, 0, GetClientOfUserId(g_iAcidAttackerUserid[entity]), flDamage, DMG_ACID);
	g_flAcidAttackNextAttack[entity] = fTime + ACID_ATTACK_INTERVAL;
	AcidOnFloor(entity);
}

public MRESReturn PreDetonate(int pThis)
{
	if(g_flPreventBreakTime[pThis] > GetGameTime())
		return MRES_Supercede;
	return MRES_Ignored;
}

public MRESReturn PreExplodeVomit(int pThis)
{
	BreakBilejar(pThis, GetEntPropEnt(pThis, Prop_Send, "m_hThrower"));
	return MRES_Supercede;
}

void BreakBilejar(int entity, int attacker)
{
	static float vecJarPos[3];
	static float vecPlayerPos[3];
	
	int iTeam;
	float fTime = GetGameTime();
	Entity_GetAbsOrigin(entity, vecJarPos);
	
	for(int i = 1; i <= MaxClients; ++i)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		
		iTeam = GetClientTeam(i);
		
		switch(iTeam)
		{
			case 2:
			{
				if(attacker != i)
					continue;
				
				GetEntityAbsOrigin(i, vecPlayerPos, true);
				if(GetVectorDistance(vecJarPos, vecPlayerPos) > VOMIT_JAR_RADIUS_SURVIVOR)
					continue;
				
				g_flAcidAttackTime[i] = fTime + VOMIT_JAR_LIFETIME_SURVIVOR * ACID_LIFETIME_SURVIVOR;
				g_flAcidAttackNextAttack[i] = fTime + ACID_ATTACK_INTERVAL_SURVIVOR;
				g_iAcidAttackerUserid[i] = 0;
				
				SDKCall(hOnVomitedUpon, i, (attacker == -1 ? i : attacker), 0);
			}
			case 3:
			{
				if(GetEntProp(i, Prop_Send, "m_isGhost", 1) > 0)
					continue;
				
				GetEntityAbsOrigin(i, vecPlayerPos, true);
				if(GetVectorDistance(vecJarPos, vecPlayerPos) > VOMIT_JAR_RADIUS)
					continue;
				
				g_flAcidAttackTime[i] = fTime + VOMIT_JAR_LIFETIME * ACID_LIFETIME;
				g_flAcidAttackNextAttack[i] = fTime + ACID_ATTACK_INTERVAL;
				g_iAcidAttackerUserid[i] = (attacker > 0 && attacker < MaxClients+1 ? GetClientUserId(attacker) : 0);
				
				SDKCall(hOnVomitedUpon, i, (attacker == -1 ? i : attacker), 0);
			}
		}
	}
	
	for(int i = MaxClients+1; i <= 2048; ++i)
	{
		if(!IsCommonOrWitch(i) || GetEntProp(i, Prop_Data, "m_iHealth") <= 0)
			continue;
		
		GetEntityAbsOrigin(i, vecPlayerPos, true);
		if(GetVectorDistance(vecJarPos, vecPlayerPos) > VOMIT_JAR_RADIUS)
			continue;
		
		SDKHook(i, SDKHook_Think, AcidThink);
	
		g_flAcidAttackTime[i] = fTime + VOMIT_JAR_LIFETIME * ACID_LIFETIME;
		g_flAcidAttackNextAttack[i] = fTime + ACID_ATTACK_INTERVAL;
		g_iAcidAttackerUserid[i] = (attacker > 0 && attacker < MaxClients+1 ? GetClientUserId(attacker) : 0);
		
		SDKCall(hOnVomitedUpon_NB, i, attacker);
	}
	
	L4D_TE_Create_Particle(vecJarPos, _, g_iVomitJar_ParticleReplacement);
	L4D_TE_Create_Particle(vecJarPos, _, g_iVomitJar_AcidSplash);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(entity < 1)
		return;
	
	g_flPreventBreakTime[entity] = 0.0;
	g_flAcidAttackTime[entity] = 0.0;
	if(classname[0] != 'v' || !StrEqual(classname, "vomitjar_projectile"))
		return;
	
	SDKHook(entity, SDKHook_SpawnPost, AttachTrail);
}

public void AttachTrail(int entity)
{
	SDKUnhook(entity, SDKHook_SpawnPost, AttachTrail);
	SDKHook(entity, SDKHook_StartTouch, StartTouch);	
	g_flPreventBreakTime[entity] = GetGameTime() + 0.2;
	JarTrail(entity);
}

public Action StartTouch(int entity, int other)
{
	if(other < 1 || other > MaxClients)
		return Plugin_Continue;
	
	if(GetClientTeam(other) != 2 || !IsPlayerAlive(other))
		return Plugin_Continue;
	return Plugin_Handled;
}


//Credit smlib https://github.com/bcserv/smlib
/*
 * Rewrite of FindStringIndex, because in my tests
 * FindStringIndex failed to work correctly.
 * Searches for the index of a given string in a string table. 
 * 
 * @param tableidx		A string table index.
 * @param str			String to find.
 * @return				String index if found, INVALID_STRING_INDEX otherwise.
 */
stock int __FindStringIndex2(int tableidx, const char[] str)
{
	char buf[1024];

	int numStrings = GetStringTableNumStrings(tableidx);
	for (int i=0; i < numStrings; i++) {
		ReadStringTable(tableidx, i, buf, sizeof(buf));
		
		if (StrEqual(buf, str)) {
			return i;
		}
	}
	
	return INVALID_STRING_INDEX;
}

void AcidOnFloor(int iVictim)
{
	static bool bisBloodNear;
	static float fPos[3];
	static float fTmpPos[3];
	static float fNow;
	static Handle hArray = INVALID_HANDLE;
	
	GetEntPropVector(iVictim, Prop_Data, "m_vecAbsOrigin", fPos);

	if(hArray == INVALID_HANDLE) 
		hArray = CreateArray(4); //0: Pos[0] 1: Pos[1] 3: Pos[2] 4:Time
	
	bisBloodNear = false;
	fNow = GetEngineTime();
	 
	for(int i = GetArraySize(hArray) - 1; i > -1; i--)
	{
		static float fTime;
		fTime = GetArrayCell(hArray, i, 3);
		
		if(fTime < fNow)
		{
			RemoveFromArray(hArray, i);
			continue;
		}
		
		//Skip the checks, we already know
		if(bisBloodNear)
			continue;
		
		fTmpPos[0] = GetArrayCell(hArray, i, 0);
		fTmpPos[1] = GetArrayCell(hArray, i, 1);
		fTmpPos[2] = GetArrayCell(hArray, i, 2);
		
		if(GetVectorDistance(fTmpPos, fPos) < 50.0)
			bisBloodNear = true;
	}
	
	if(bisBloodNear)
		return;
	
	int iIndex = PushArrayCell(hArray, 0); //Just to get the new created index
	SetArrayCell(hArray, iIndex, fPos[0], 0);
	SetArrayCell(hArray, iIndex, fPos[1], 1);
	SetArrayCell(hArray, iIndex, fPos[2], 2);
	SetArrayCell(hArray, iIndex, fNow + 7.5, 3);
	
	L4D_TE_Create_Particle(fPos, _, g_iVomitJar_AcidTrail);
}

stock void JarTrail(int iTarget)
{
	/*
	int iEntity = CreateEntityByName("info_particle_system");
	if(iEntity < 1)
		return;

	if(iEntity > ENTITY_SAFE_LIMIT)
	{
		RemoveEntity(iEntity);
		return;
	}

	DispatchKeyValue(iEntity, "effect_name", "spitter_slime_trail");
	

	DispatchSpawn(iEntity);
	ActivateEntity(iEntity);
	
	AcceptEntityInput(iEntity, "Start");
	SetVariantString("!activator");
	AcceptEntityInput(iEntity, "SetParent", iTarget);
	
	TeleportEntity(iEntity, view_as<float>({0.0, 0.0, 9.5}), NULL_VECTOR, NULL_VECTOR);
	*/
	
	static float vecPos[3];
	Entity_GetAbsOrigin(iTarget, vecPos);
	vecPos[2] += 9.5;
	
	//TE_SetupParticleFollowEntity_Name("spitter_slime_trail", iTarget, vecPos);
	TE_SetupParticleFollowEntity(g_iVomitJar_GooTrail, iTarget);
	TE_SendToAll();
}