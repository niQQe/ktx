/*
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 *
 *  $Id$
 */

// motd.c
#include "g_local.h"

void PMOTDThink(void)
{
	int i;
	char buf[2048] =
		{ 0 };
	char *s;

	// remove MOTD in some cases
	if ((self->attack_finished < g_globalvars.time) // expired
			|| (!k_matchLess && match_in_progress)  // non matchless and (match has began or countdown)
			|| (k_matchLess && match_in_progress == 1) // matchless and countdown
			|| (PROG_TO_EDICT(self->s.v.owner)->attack_finished > g_globalvars.time) // player fire something, so he wanna play, not reading motd
			|| PROG_TO_EDICT(self->s.v.owner)->s.v.button0) // holding +attack: dismiss even with no weapon (pre-match waiting state)
	{
		if (self->attack_finished < g_globalvars.time)
		{
			G_centerprint(PROG_TO_EDICT(self->s.v.owner), "%s", "");
		}

		ent_remove(self);

		return;
	}

	if (PROG_TO_EDICT(self->s.v.owner)->wp_stats || PROG_TO_EDICT(self->s.v.owner)->sc_stats
			|| PROG_TO_EDICT(self->s.v.owner)->shownick_time)
	{
		self->s.v.nextthink = g_globalvars.time + 1; // do not interference with +wp_stats or +scores and shownick

		return;
	}

	// --- QWLeague matchmade splash -------------------------------------
	// On a matchmade server (k_match_id is set by the agent) this is the ONLY
	// splash the player sees — it fully replaces the stock KTX MOTD below.
	// It is cleared automatically on fire / match start by the removal check
	// at the top of this function. QW centerprint is text-only, so the
	// "graphics" are a framed window drawn with the gold border glyphs
	// (\235 = left cap, \236 = bar, \237 = right cap).
	{
		gedict_t *owner = PROG_TO_EDICT(self->s.v.owner);
		char *match_id = cvar_string("k_match_id");

		if (!owner->isBot && match_id[0])
		{
			char *url = cvar_string("k_qwleague_url");
			qbool authed = ezinfokey(owner, "qwleague_token")[0] != 0;

			// Plain centered text — the QW client centers each centerprint line
			// on screen, so no manual padding or framing glyphs.
			strlcat(buf, va("%s\n\n", redtext("QW LEAGUE")), sizeof(buf));

			if (!authed && url[0])
			{
				// Player hasn't linked their token on this server yet. This
				// splash stays up (manual fire-to-dismiss, see MakeMOTD) so they
				// have time to read the instructions and set their token.
				strlcat(buf, "Sign up and get your token at\n", sizeof(buf));
				strlcat(buf, va("%s\n\n", redtext(url)), sizeof(buf));
				strlcat(buf, "then in console:\n", sizeof(buf));
				strlcat(buf,
						va("%s\n", redtext("setinfo qwleague_token <your-token>")),
						sizeof(buf));
				strlcat(buf, va("\n%s", redtext("press FIRE to dismiss")),
						sizeof(buf));
			}
			else
			{
				// Authed + assigned — just identify the QWLeague server. No
				// match-fill status; this splash auto-dismisses shortly (see
				// MakeMOTD), so there's no "press fire" prompt.
				strlcat(buf, va("Server #%s\n", redtext(match_id)), sizeof(buf));
				if (url[0])
				{
					strlcat(buf, va("%s\n", redtext(url)), sizeof(buf));
				}
			}

			G_centerprint(owner, "%s", buf);
			self->s.v.nextthink = g_globalvars.time + 0.7;
			return;
		}
	}

	for (i = 1; i <= MOTD_LINES; i++)
	{
		if (strnull(s = cvar_string(va("k_motd%d", i))))
		{
			continue;
		}

		strlcat(buf, s, sizeof(buf));
		strlcat(buf, "\n", sizeof(buf));
	}

	// no "welcome" - if k_motd keys is present - because admin may wanna customize this
	if (strnull(buf))
	{
		strlcat(buf, "Welcome\n\n", sizeof(buf));
	}

	strlcat(buf, "\n\235\236\236\236\236\236\236\236\236\236\236\236\236\236\236\237\n\n",
			sizeof(buf));
	strlcat(buf,
			va("Running %s %s", redtext(cvar_string("qwm_name")),
				redtext(cvar_string("qwm_version"))),
			sizeof(buf));
	if (strlen(cvar_string("qws_name")) && strlen(cvar_string("qws_version")))
	{
		strlcat(buf,
				va(" on %s %s", redtext(cvar_string("qws_name")),
					redtext(cvar_string("qws_version"))),
				sizeof(buf));
	}

	strlcat(buf,
			va("\n\nType \"%s\" for available commands\nType \"%s\" for server details",
				redtext("commands"), redtext("about")),
			sizeof(buf));

	// (QWLeague matchmade splash is handled above and returns early. The code
	// here is the stock KTX MOTD, kept only as a fallback for non-matchmade
	// servers where k_match_id is unset.)

	G_centerprint(PROG_TO_EDICT(self->s.v.owner), "%s", buf);

	self->s.v.nextthink = g_globalvars.time + 0.7;
}

void SMOTDThink(void)
{
	PMOTDThink(); // equal motd for player and spectator now
}

void MOTDThinkX(void)
{
	gedict_t *owner = PROG_TO_EDICT(self->s.v.owner);

	// FIXME: server work around, frags are not restored, ie showed as 0, force update frags manually
	if (owner->s.v.frags && ((int)(owner - world - 1) >= 0)
			&& ((int)(owner - world - 1) < MAX_CLIENTS))
	{
		WriteByte(MSG_ALL, SVC_UPDATEFRAGS); // update frags
		WriteByte(MSG_ALL, (int)(owner - world - 1));
		WriteShort(MSG_ALL, owner->s.v.frags);
	}

	// select MOTD for spectator or player
	self->think = (func_t)(owner->ct == ctSpec ? SMOTDThink : PMOTDThink);
	self->s.v.nextthink = g_globalvars.time + 0.3;

	if (owner->k_stuff)
	{
		if (k_matchLess) // remove motd if player already stuffed, because them probably sow motd already one time
		{
			ent_remove(self);
		}
	}

	// stuff or not to stuff, that the question!
	if (!(owner->k_stuff & STUFF_MAPS))
	{
		StuffMaps(owner);
	}
	else if (!(owner->k_stuff & STUFF_COMMANDS))
	{
		StuffModCommands(owner);
	}
}

void MakeMOTD(void)
{
	gedict_t *motd;
	int i = bound(0, cvar("k_motd_time"), 30);
	qbool needs_qwleague = !self->isBot
			&& cvar_string("k_qwleague_url")[0]
			&& !ezinfokey(self, "qwleague_token")[0];
	// On a matchmade server the QWLeague splash stays up until the player
	// fires or the match starts, not just k_motd_time seconds.
	qbool mm_splash = !self->isBot && cvar_string("k_match_id")[0];

	motd = spawn();
	motd->classname = "motd";
	motd->s.v.owner = EDICT_TO_PROG(self);
	motd->think = (func_t) MOTDThinkX;
	motd->s.v.nextthink = g_globalvars.time + 0.1;

	if (needs_qwleague)
	{
		// Unauthed: persistent so the player has time to read the signup/token
		// instructions and dismiss manually (PMOTDThink removes on +attack).
		motd->attack_finished = g_globalvars.time + 3600;
	}
	else if (mm_splash)
	{
		// Authed matchmade: brief server-info splash that auto-dismisses (no
		// "press fire"), so it's gone shortly after they connect. Firing still
		// removes it early via PMOTDThink's +attack check.
		motd->attack_finished = g_globalvars.time + 10;
	}
	else
	{
		motd->attack_finished = g_globalvars.time + (i ? i : (k_matchLess ? 3 : 7));
	}
}

void RemoveMOTD(void)
{
	gedict_t *motd;
	int owner = EDICT_TO_PROG(self);

	for (motd = world; (motd = find(motd, FOFCLSN, "motd"));) // self MOTD
	{
		if (owner == motd->s.v.owner)
		{
			ent_remove(motd);
		}
	}
}
