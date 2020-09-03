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
#include <dhooks>

#pragma newdecls required

#define GAMEDATA "Bile_Bomb_rework"
#define PLUGIN_VERSION	"1.0"


#define ENTITY_SAFE_LIMIT 1900

#define ACID_ATTACK_INTERVAL 0.1
#define ACID_DAMAGE_PERCENT 0.01
#define ACID_ATTACK_INTERVAL_SURVIVOR 0.1
#define ACID_DAMAGE_PERCENT_SURVIVORS 0.01

#define ACID_LIFETIME 0.5 //m_itTimer
#define ACID_LIFETIME_SURVIVOR 0.15 //m_itTimer

#define VOMIT_JAR_LIFETIME_SURVIVOR 20
#define VOMIT_JAR_RADIUS_SURVIVOR 85
#define VOMIT_JAR_RADIUS 150
#define VOMIT_JAR_LIFETIME 20

Handle hOnVomitedUpon;

bool g_bShouldIntervene = false;
int g_iThrower = -1;
int g_iEffectIndex = -1;
int g_iVomitjar_ParticleIndex = INVALID_STRING_INDEX;
int g_iVomitJar_ParticleReplacement = INVALID_STRING_INDEX;
int g_iVomitJar_AcidSplash = INVALID_STRING_INDEX;
int g_iVomitJar_AcidTrail = INVALID_STRING_INDEX;

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
	
	MemoryPatch vomitJarMobCall = MemoryPatch.CreateFromConf(hGamedata, "CVomitJarProjectile::ExplodeVomit()::mobspawn_Patch");
	if(!vomitJarMobCall.Validate())
		SetFailState("Unable to load offset signatures differ 'CVomitJarProjectile::ExplodeVomit()::mobspawn_Patch'.", GAMEDATA);
	
	if(!vomitJarMobCall.Enable())
		PrintToServer("Patch already applied? 'CVomitJarProjectile::ExplodeVomit()::mobspawn_Patch'");
	
	Handle hDetour;
	hDetour = DHookCreateFromConf(hGamedata, "CTerrorPlayer::OnHitByVomitJar");
	if(!hDetour)
		SetFailState("Failed to find 'CTerrorPlayer::OnHitByVomitJar' signature");
	
	if(!DHookEnableDetour(hDetour, false, TerrorPlayerOnHitByVomitJar))
		SetFailState("Failed to detour 'CTerrorPlayer::OnHitByVomitJar'");
	
	hDetour = DHookCreateFromConf(hGamedata, "Infected::OnHitByVomitJar");
	if(!hDetour)
		SetFailState("Failed to find 'Infected::OnHitByVomitJar' signature");
	
	if(!DHookEnableDetour(hDetour, false, InfectedOnHitByVomitJar))
		SetFailState("Failed to detour 'Infected::OnHitByVomitJar'");
	
	hDetour = DHookCreateFromConf(hGamedata, "CVomitJarProjectile::ExplodeVomit");
	if(!hDetour)
		SetFailState("Failed to find 'CVomitJarProjectile::ExplodeVomit' signature");
	
	if(!DHookEnableDetour(hDetour, false, PreExplodeVomit))
		SetFailState("Failed to detour 'CVomitJarProjectile::ExplodeVomit'");
	if(!DHookEnableDetour(hDetour, true, PostExplodeVomit))
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
	
	delete hGamedata;
	
	HookConVarChange(FindConVar("vomitjar_duration_survivor"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_radius_survivors"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_radius"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_duration_infected_pz"), CvarsChanged);
	HookConVarChange(FindConVar("vomitjar_duration_infected_bot"), CvarsChanged);
	CvarsChange();
	
	AddTempEntHook("EffectDispatch", TEParticleHook);
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
	g_iVomitjar_ParticleIndex = __FindStringIndex2(particleEffectNames, "vomit_jar");
	g_iVomitJar_ParticleReplacement = __FindStringIndex2(particleEffectNames, "smoker_smokecloud");
	g_iVomitJar_AcidSplash = PrecacheParticleSystem("spitter_areaofdenial");
	g_iVomitJar_AcidTrail = PrecacheParticleSystem("spitter_areaofdenial_base_refract");
	
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
		SDKHooks_TakeDamage(client, 0, GetClientOfUserId(g_iAcidAttackerUserid[client]), float(RoundToCeil(GetEntProp(client, Prop_Data, "m_iMaxHealth", 4) * ACID_DAMAGE_PERCENT)), DMG_ACID);
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

public MRESReturn InfectedOnHitByVomitJar(int pThis, Handle hParams)
{
	if(DHookIsNullParam(hParams, 1))
		DHookSetParam(hParams, 1, g_iThrower);//busted always seems to be passed -1
	
	if(!g_bShouldIntervene)
		return MRES_Handled;
	
	if(GetEntProp(pThis, Prop_Data, "m_iHealth") <= 0)
		return MRES_Ignored;
	
	SDKHook(pThis, SDKHook_Think, AcidThink);
	
	float fTime = GetGameTime();
	g_flAcidAttackTime[pThis] = fTime + VOMIT_JAR_LIFETIME * ACID_LIFETIME;
	g_flAcidAttackNextAttack[pThis] = fTime + ACID_ATTACK_INTERVAL;
	g_iAcidAttackerUserid[pThis] = (g_iThrower > 0 && g_iThrower < MaxClients+1 ? GetClientUserId(g_iThrower) : 0);
	return MRES_Handled;
}

public MRESReturn TerrorPlayerOnHitByVomitJar(int pThis, Handle hParams)
{
	if(!g_bShouldIntervene)
		return MRES_Ignored;
	
	int iTeam = GetClientTeam(pThis);
	float fTime = GetGameTime();
	if(iTeam == 2)
	{
		if(g_iThrower != pThis)
			return MRES_Supercede;
		
		g_flAcidAttackTime[pThis] = fTime + VOMIT_JAR_LIFETIME_SURVIVOR * ACID_LIFETIME_SURVIVOR;
		g_flAcidAttackNextAttack[pThis] = fTime + ACID_ATTACK_INTERVAL_SURVIVOR;
		g_iAcidAttackerUserid[pThis] = 0;
	}
	else if(iTeam == 3)
	{
		g_flAcidAttackTime[pThis] = fTime + VOMIT_JAR_LIFETIME * ACID_LIFETIME;
		g_flAcidAttackNextAttack[pThis] = fTime + ACID_ATTACK_INTERVAL;
		g_iAcidAttackerUserid[pThis] = (g_iThrower > 0 && g_iThrower < MaxClients+1 ? GetClientUserId(g_iThrower) : 0);
	}
	

	SDKCall(hOnVomitedUpon, pThis, (g_iThrower == -1 ? pThis : g_iThrower), 0);
	return MRES_Supercede;
}

public MRESReturn PreExplodeVomit(int pThis)
{
	g_iThrower = GetEntPropEnt(pThis, Prop_Send, "m_hThrower");
	g_bShouldIntervene = true;
	return MRES_Ignored;
}

public MRESReturn PostExplodeVomit(int pThis)
{
	g_iThrower = -1;
	g_bShouldIntervene = false;
	return MRES_Ignored;
}

public Action TEParticleHook(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!g_bShouldIntervene || g_iEffectIndex != TE_ReadNum("m_iEffectName"))
		return Plugin_Continue;
	
	if(TE_ReadNum("m_nHitBox") == g_iVomitjar_ParticleIndex)
	{
		float flPos[3];
		flPos[0] = TE_ReadFloat("m_vOrigin.x"); 
		flPos[1] = TE_ReadFloat("m_vOrigin.y"); 
		flPos[2] = TE_ReadFloat("m_vOrigin.z"); 
		L4D_TE_Create_Particle(flPos, _, g_iVomitJar_ParticleReplacement);
		L4D_TE_Create_Particle(flPos, _, g_iVomitJar_AcidSplash);
		//TE_WriteNum("m_nHitBox", g_iVomitJar_ParticleReplacement);//why you no work :c
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(entity < 1)
		return;
	
	g_flPreventBreakTime[entity] = 0.0;
	g_flAcidAttackTime[entity] = 0.0;
	if(g_bShouldIntervene && classname[0] == 'i' && StrEqual(classname, "info_goal_infected_chase", false))
	{
		SDKHook(entity, SDKHook_SpawnPost, RemoveChaseEntity);
		return;
	}
	
	if(classname[0] != 'v' || !StrEqual(classname, "vomitjar_projectile"))
		return;
	
	SDKHook(entity, SDKHook_SpawnPost, AttachTrail);
}

public void RemoveChaseEntity(int entity)
{
	SetVariantString("OnUser1 !self:Kill::1:-1");
	AcceptEntityInput(entity, "AddOutput");
	AcceptEntityInput(entity, "FireUser1");
	//RemoveEntity(entity);
}

public void AttachTrail(int entity)
{
	SDKUnhook(entity, SDKHook_SpawnPost, AttachTrail);
	SDKHook(entity, SDKHook_StartTouch, StartTouch);	
	g_flPreventBreakTime[entity] = GetGameTime() + 0.12;
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
		
		if(GetVectorDistance(fTmpPos, fPos) < 60.0)
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

stock bool L4D_TE_Create_Particle(float fParticleStartPos[3]={0.0, 0.0, 0.0}, 
								float fParticleEndPos[3]={0.0, 0.0, 0.0}, 
								int iParticleIndex=-1, 
								int iEntIndex=0,
								float fDelay=0.0,
								bool SendToAll=true,
								char sParticleName[64]="",
								int iAttachmentIndex=0,
								float fParticleAngles[3]={0.0, 0.0, 0.0}, 
								int iFlags=0,
								int iDamageType=0,
								float fMagnitude=0.0,
								float fScale=1.0,
								float fRadius=0.0)
{
	TE_Start("EffectDispatch");
	
	static EngineVersion IsEngine;
	if(IsEngine == Engine_Unknown)
		IsEngine = GetEngineVersion();
	
	TE_WriteFloat(IsEngine == Engine_Left4Dead2 ? "m_vOrigin.x"	:"m_vStart[0]", fParticleStartPos[0]);
	TE_WriteFloat(IsEngine == Engine_Left4Dead2 ? "m_vOrigin.y"	:"m_vStart[1]", fParticleStartPos[1]);
	TE_WriteFloat(IsEngine == Engine_Left4Dead2 ? "m_vOrigin.z"	:"m_vStart[2]", fParticleStartPos[2]);
	TE_WriteFloat(IsEngine == Engine_Left4Dead2 ? "m_vStart.x"	:"m_vOrigin[0]", fParticleEndPos[0]);//end point usually for bulletparticles or ropes
	TE_WriteFloat(IsEngine == Engine_Left4Dead2 ? "m_vStart.y"	:"m_vOrigin[1]", fParticleEndPos[1]);
	TE_WriteFloat(IsEngine == Engine_Left4Dead2 ? "m_vStart.z"	:"m_vOrigin[2]", fParticleEndPos[2]);
	
	static int iEffectIndex = INVALID_STRING_INDEX;
	if(iEffectIndex < 0)
	{
		iEffectIndex = __FindStringIndex2(FindStringTable("EffectDispatch"), "ParticleEffect");
		if(iEffectIndex == INVALID_STRING_INDEX)
			SetFailState("Unable to find EffectDispatch/ParticleEffect indexes");
		
	}
	
	TE_WriteNum("m_iEffectName", iEffectIndex);
	
	if(iParticleIndex < 0)
	{
		static int iParticleStringIndex = INVALID_STRING_INDEX;
		iParticleStringIndex = __FindStringIndex2(iEffectIndex, sParticleName);
		if(iParticleStringIndex == INVALID_STRING_INDEX)
			return false;
		
		TE_WriteNum("m_nHitBox", iParticleStringIndex);
	}
	else
		TE_WriteNum("m_nHitBox", iParticleIndex);
	
	TE_WriteNum("entindex", iEntIndex);
	TE_WriteNum("m_nAttachmentIndex", iAttachmentIndex);
	
	TE_WriteVector("m_vAngles", fParticleAngles);
	
	TE_WriteNum("m_fFlags", iFlags);
	TE_WriteFloat("m_flMagnitude", fMagnitude);// saw this being used in pipebomb needs testing what it does probs shaking screen?
	TE_WriteFloat("m_flScale", fScale);
	TE_WriteFloat("m_flRadius", fRadius);// saw this being used in pipebomb needs testing what it does probs shaking screen?
	TE_WriteNum("m_nDamageType", iDamageType);// this shit is required dunno why for attachpoint emitting valve probs named it wrong
	
	if(SendToAll)
		TE_SendToAll(fDelay);
	
	return true;
}

stock void JarTrail(int iTarget)
{
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
}