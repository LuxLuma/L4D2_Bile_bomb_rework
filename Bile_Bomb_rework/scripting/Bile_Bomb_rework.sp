/*  
*    Copyright (C) 2021  LuxLuma		acceliacat@gmail.com
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

//FIXME make var names consistent stop copy and pasting old code

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <lux_library>
#include <dhooks>

#pragma newdecls required

#define GAMEDATA "Bile_Bomb_rework"
#define PLUGIN_VERSION	"1.1.8"

Handle hOnVomitedUpon;
Handle hOnVomitedUpon_NB;

ConVar hCvar_AcidLifeTime;
ConVar hCvar_AcidLifeTime_Survivor;

float g_flAcidLifetime;
float g_flAcidLifetime_Survivor;

ConVar hCvar_AcidAttack_Interval;
ConVar hCvar_AcidAttack_Interval_Survivor;

float g_flAcidAttack_Interval;
float g_flAcidAttack_Interval_Survivor;

ConVar hCvar_AcidAttack_Damage_Percent;
ConVar hCvar_AcidAttack_Damage_Percent_Survivor;

float g_flAcidAttack_Damage_Percent;
float g_flAcidAttack_Damage_Percent_Survivor;

ConVar hCvar_VomitJar_Radius;
ConVar hCvar_VomitJar_Radius_Survivor;

float g_flVomitJar_Radius;
float g_flVomitJar_Radius_Survivor;

ConVar hCvar_AcidPool_UpdateInterval;
ConVar hCvar_AcidHit_SoundInterval;

float g_flAcidPool_UpdateInterval;
float g_flAcidHit_SoundInterval;

ConVar hCvar_Vomitjar_BreakImmunity_Time;
float g_flVomitjar_BreakImmunity_Time;

int g_iVomitJar_ParticleReplacement = INVALID_STRING_INDEX;
int g_iVomitJar_AcidSplash = INVALID_STRING_INDEX;
int g_iVomitJar_AcidTrail = INVALID_STRING_INDEX;
int g_iVomitJar_GooTrail = INVALID_STRING_INDEX;


float g_flPreventBreakTime[2048+1];

enum struct AcidData
{
	float flAcidAttackTime;
	float flAcidAttackNextAttack;
	int AcidAttackerUserid;
	float flAcidHitSoundInterval;
	float flAcidPoolUpdateInterval;
}

AcidData g_AcidData[2048+1];

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
	description = "Merge vomit and spitter acid in bile bomb",
	version = PLUGIN_VERSION,
	url = "https://github.com/LuxLuma/L4D2_Bile_bomb_rework"
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
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	
	hOnVomitedUpon_NB = EndPrepSDKCall();
	if(hOnVomitedUpon_NB == null)
		SetFailState("Unable to prep SDKCall 'Infected::OnHitByVomitJar");
	
	delete hGamedata;
	
	CreateConVar("bb_rework_version", PLUGIN_VERSION, "", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	hCvar_AcidLifeTime = CreateConVar("bb_acid_life", "15.0", "Acid effect life time", FCVAR_NOTIFY);
	hCvar_AcidLifeTime_Survivor = CreateConVar("bb_acid_life_survivor", "3.0", "Acid effect life time survivors", FCVAR_NOTIFY);
	hCvar_AcidAttack_Interval = CreateConVar("bb_acid_attack_interval", "0.1", "Acid attack interval", FCVAR_NOTIFY);
	hCvar_AcidAttack_Interval_Survivor = CreateConVar("bb_acid_attack_interval_survivor", "0.1", "Acid attack interval survivors", FCVAR_NOTIFY);
	hCvar_AcidAttack_Damage_Percent = CreateConVar("bb_acid_damage_percent", "0.006", "Acid attack percent max health damage to deal per interval (min 1 damage regardless)", FCVAR_NOTIFY);
	hCvar_AcidAttack_Damage_Percent_Survivor = CreateConVar("bb_acid_damage_percent_survivor", "0.0", "Acid attack percent max health damage to deal per interval survivor (min 1 damage regardless)", FCVAR_NOTIFY);
	hCvar_VomitJar_Radius = CreateConVar("bb_vomitjar_radius", "200.0", "Vomitjar bile radius", FCVAR_NOTIFY);
	hCvar_VomitJar_Radius_Survivor = CreateConVar("bb_vomitjar_radius_survivor", "100.0", "vomitjar bile radius survivors, only affects thrower", FCVAR_NOTIFY);
	hCvar_AcidPool_UpdateInterval = CreateConVar("bb_acid_pool_update_interval", "0.1", "Update interval to try spawning a acid pool(Visual only) does not deal damage", FCVAR_NOTIFY);
	hCvar_AcidHit_SoundInterval = CreateConVar("bb_acid_hit_sound_interval", "0.5", "Sound emit interval for acid attack", FCVAR_NOTIFY);
	hCvar_Vomitjar_BreakImmunity_Time = CreateConVar("bb_vomitjar_break_immunity_time", "0.2", "Cannot be broken on impacts for set time after spawning, stationery bile bombs will not break without help", FCVAR_NOTIFY, _, _, true, 0.5);
	
	hCvar_AcidLifeTime.AddChangeHook(CvarsChanged);
	hCvar_AcidLifeTime_Survivor.AddChangeHook(CvarsChanged);
	hCvar_AcidAttack_Interval.AddChangeHook(CvarsChanged);
	hCvar_AcidAttack_Interval_Survivor.AddChangeHook(CvarsChanged);
	hCvar_AcidAttack_Damage_Percent.AddChangeHook(CvarsChanged);
	hCvar_AcidAttack_Damage_Percent_Survivor.AddChangeHook(CvarsChanged);
	hCvar_VomitJar_Radius.AddChangeHook(CvarsChanged);
	hCvar_VomitJar_Radius_Survivor.AddChangeHook(CvarsChanged);
	hCvar_AcidPool_UpdateInterval.AddChangeHook(CvarsChanged);
	hCvar_AcidHit_SoundInterval.AddChangeHook(CvarsChanged);
	hCvar_Vomitjar_BreakImmunity_Time.AddChangeHook(CvarsChanged);
	CvarsChange();
	
	AutoExecConfig(true, "bile_bomb_rework");
}

public void CvarsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	CvarsChange();
}

void CvarsChange()
{
	g_flAcidLifetime = hCvar_AcidLifeTime.FloatValue;
	g_flAcidLifetime_Survivor = hCvar_AcidLifeTime_Survivor.FloatValue;
	g_flAcidAttack_Interval = hCvar_AcidAttack_Interval.FloatValue;
	g_flAcidAttack_Interval_Survivor = hCvar_AcidAttack_Interval_Survivor.FloatValue;
	g_flAcidAttack_Damage_Percent = hCvar_AcidAttack_Damage_Percent.FloatValue;
	g_flAcidAttack_Damage_Percent_Survivor = hCvar_AcidAttack_Damage_Percent_Survivor.FloatValue;
	g_flVomitJar_Radius = hCvar_VomitJar_Radius.FloatValue;
	g_flVomitJar_Radius_Survivor = hCvar_VomitJar_Radius_Survivor.FloatValue;
	g_flAcidPool_UpdateInterval = hCvar_AcidPool_UpdateInterval.FloatValue;
	g_flAcidHit_SoundInterval = hCvar_AcidHit_SoundInterval.FloatValue;
	g_flVomitjar_BreakImmunity_Time = hCvar_Vomitjar_BreakImmunity_Time.FloatValue;
}

public void OnMapStart()
{
	g_iVomitJar_ParticleReplacement = Precache_Particle_System("smoker_smokecloud");
	g_iVomitJar_AcidSplash = Precache_Particle_System("spitter_areaofdenial");
	g_iVomitJar_AcidTrail = Precache_Particle_System("spitter_areaofdenial_base_refract");
	g_iVomitJar_GooTrail = Precache_Particle_System("spitter_slime_trail");
	
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
	
	if(g_AcidData[client].flAcidAttackTime < fTime)
		return;
	
	if(g_AcidData[client].flAcidPoolUpdateInterval < fTime)
	{
		g_AcidData[client].flAcidPoolUpdateInterval = fTime + g_flAcidPool_UpdateInterval;
		AcidOnFloor(client);
	}
	
	if(g_AcidData[client].flAcidAttackNextAttack > fTime)
		return;
	
	if(team == 2)
	{
		SDKHooks_TakeDamage(client, 0, 0, 1.0 + float(RoundToFloor(GetEntProp(client, Prop_Data, "m_iMaxHealth", 4) * g_flAcidAttack_Damage_Percent_Survivor)), DMG_ACID);
		g_AcidData[client].flAcidAttackNextAttack = fTime + g_flAcidAttack_Interval_Survivor;
	}
	else if(team == 3)
	{
		SDKHooks_TakeDamage(client, 0, GetClientOfUserId(g_AcidData[client].AcidAttackerUserid), 1.0 + float(RoundToFloor(GetEntProp(client, Prop_Data, "m_iMaxHealth", 4) * g_flAcidAttack_Damage_Percent)), DMG_ACID);
		g_AcidData[client].flAcidAttackNextAttack = fTime + g_flAcidAttack_Interval;
	}
	
	if(g_AcidData[client].flAcidHitSoundInterval > fTime)
		return;
	
	g_AcidData[client].flAcidHitSoundInterval = fTime + g_flAcidHit_SoundInterval;
	EmitSoundToAll(g_sRandomSound[GetRandomInt(0, 5)], client, SNDCHAN_STATIC, SNDLEVEL_CAR, _, SNDVOL_NORMAL);
}

public void AcidThink(int entity)
{
	if(GetEntProp(entity, Prop_Data, "m_iHealth") <= 0)//better way?
		return;
	
	float fTime = GetGameTime();
	if(g_AcidData[entity].flAcidAttackTime < fTime)
		return;
	
	if(g_AcidData[entity].flAcidPoolUpdateInterval < fTime)
	{
		g_AcidData[entity].flAcidPoolUpdateInterval = fTime + g_flAcidPool_UpdateInterval;
		AcidOnFloor(entity);
	}
	
	if(g_AcidData[entity].flAcidAttackNextAttack > fTime)
		return;
	
	float flDamage = 1.0 + float(RoundToFloor(GetEntProp(entity, Prop_Data, "m_iMaxHealth", 4) * g_flAcidAttack_Damage_Percent));	
	SDKHooks_TakeDamage(entity, 0, GetClientOfUserId(g_AcidData[entity].AcidAttackerUserid), flDamage, DMG_ACID);
	g_AcidData[entity].flAcidAttackNextAttack = fTime + g_flAcidAttack_Interval;
}

//valve does not use touch functions to check if it should break or not when hitting players, this is done in vomitjar's own function need memory patching to get around it, maybe do this some other time.
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
	GetAbsOrigin(entity, vecJarPos);
	
	//fixes sound bug commons got crazy appears to only affect linux
	int iEntity = CreateEntityByName("info_goal_infected_chase");
	DispatchSpawn(iEntity);
	TeleportEntity(iEntity, vecJarPos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(iEntity, "Enable");
	
	SetVariantString("OnUser1 !self:Kill::1.0:-1");
	AcceptEntityInput(iEntity, "AddOutput");
	AcceptEntityInput(iEntity, "FireUser1");
	
	//bypassed valve's native ray code for vomiting with just vector checks was way too inconsistent with bazar results
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
				
				GetAbsOrigin(i, vecPlayerPos, true);
				if(GetVectorDistance(vecJarPos, vecPlayerPos) > g_flVomitJar_Radius_Survivor)
					continue;
				
				g_AcidData[i].flAcidAttackTime = fTime + g_flAcidLifetime_Survivor;
				g_AcidData[i].flAcidAttackNextAttack = fTime + g_flAcidAttack_Interval_Survivor;
				g_AcidData[i].AcidAttackerUserid = 0;
				g_AcidData[i].flAcidHitSoundInterval = fTime + g_flAcidHit_SoundInterval;
				g_AcidData[i].flAcidPoolUpdateInterval = fTime + g_flAcidPool_UpdateInterval;
				
				SDKCall(hOnVomitedUpon, i, (attacker < 1 ? i : attacker), 0);
			}
			case 3:
			{
				if(GetEntProp(i, Prop_Send, "m_isGhost", 1) > 0)
					continue;
				
				GetAbsOrigin(i, vecPlayerPos, true);
				if(GetVectorDistance(vecJarPos, vecPlayerPos) > g_flVomitJar_Radius)
					continue;
				
				g_AcidData[i].flAcidAttackTime = fTime + g_flAcidLifetime;
				g_AcidData[i].flAcidAttackNextAttack = fTime + g_flAcidAttack_Interval;
				g_AcidData[i].AcidAttackerUserid = (attacker > 0 && attacker < MaxClients+1 ? GetClientUserId(attacker) : 0);
				g_AcidData[i].flAcidHitSoundInterval = fTime + g_flAcidHit_SoundInterval;
				g_AcidData[i].flAcidPoolUpdateInterval = fTime + g_flAcidPool_UpdateInterval;
				
				SDKCall(hOnVomitedUpon, i, (attacker < 1 ? i : attacker), 0);
			}
		}
	}
	
	for(int i = MaxClients+1; i <= 2048; ++i)
	{
		if(!IsCommonOrWitch(i) || GetEntProp(i, Prop_Data, "m_iHealth") <= 0)
			continue;
		
		GetAbsOrigin(i, vecPlayerPos, true);
		if(GetVectorDistance(vecJarPos, vecPlayerPos) > g_flVomitJar_Radius)
			continue;
		
		SDKHook(i, SDKHook_Think, AcidThink);
	
		g_AcidData[i].flAcidAttackTime = fTime + g_flAcidLifetime;
		g_AcidData[i].flAcidAttackNextAttack = fTime + g_flAcidAttack_Interval;
		g_AcidData[i].AcidAttackerUserid = (attacker > 0 && attacker < MaxClients+1 ? GetClientUserId(attacker) : 0);
		g_AcidData[i].flAcidPoolUpdateInterval = fTime + g_flAcidPool_UpdateInterval;
		
		SDKCall(hOnVomitedUpon_NB, i, (attacker < 1 ? i : attacker));
	}
	
	TE_SetupParticle(g_iVomitJar_ParticleReplacement, vecJarPos);
	TE_SendToAll();
	TE_SetupParticle(g_iVomitJar_AcidSplash, vecJarPos);
	TE_SendToAll();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(entity < 1)
		return;
	
	g_flPreventBreakTime[entity] = 0.0;
	g_AcidData[entity].flAcidAttackTime = 0.0;
	if(classname[0] != 'v' || !StrEqual(classname, "vomitjar_projectile"))
		return;
	
	SDKHook(entity, SDKHook_SpawnPost, AttachTrail);
}

public void AttachTrail(int entity)
{
	SDKUnhook(entity, SDKHook_SpawnPost, AttachTrail);
	g_flPreventBreakTime[entity] = GetGameTime() + g_flVomitjar_BreakImmunity_Time;
	JarTrail(entity);
}

void AcidOnFloor(int iVictim)
{
	static float fPos[3];
	static float fTmpPos[3];
	static Handle hArray = INVALID_HANDLE;
	
	GetEntPropVector(iVictim, Prop_Data, "m_vecAbsOrigin", fPos);

	if(hArray == INVALID_HANDLE) 
		hArray = CreateArray(4); //0: Pos[0] 1: Pos[1] 3: Pos[2] 4:Time
	
	bool bIsAcidNear;
	float fNow = GetEngineTime();
	 
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
		if(bIsAcidNear)
			continue;
		
		fTmpPos[0] = GetArrayCell(hArray, i, 0);
		fTmpPos[1] = GetArrayCell(hArray, i, 1);
		fTmpPos[2] = GetArrayCell(hArray, i, 2);
		
		if(GetVectorDistance(fTmpPos, fPos) < 50.0)
			bIsAcidNear = true;
	}
	
	if(bIsAcidNear)
		return;
	
	int iIndex = PushArrayCell(hArray, 0); //Just to get the new created index
	SetArrayCell(hArray, iIndex, fPos[0], 0);
	SetArrayCell(hArray, iIndex, fPos[1], 1);
	SetArrayCell(hArray, iIndex, fPos[2], 2);
	SetArrayCell(hArray, iIndex, fNow + 7.5, 3);
	
	TE_SetupParticle(g_iVomitJar_AcidTrail, fPos);
	TE_SendToAll();
}

void JarTrail(int iTarget)
{
	TE_SetupParticleFollowEntity(g_iVomitJar_GooTrail, iTarget);
	TE_SendToAll();
}

bool IsCommonOrWitch(int iEntity)
{
	static char sClassName[9];
	
	if(!IsValidEntity(iEntity))
		return false;
	
	GetEntPropString(iEntity, Prop_Data, "m_iClassname", sClassName, sizeof(sClassName));
	if(sClassName[0] != 'i' && sClassName[0] != 'w')
	{
		return false;
	}
	
	if(!StrEqual(sClassName, "infected") && !StrEqual(sClassName, "witch"))
	{
		return false;
	}
	return true;
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