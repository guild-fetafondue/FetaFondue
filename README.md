# :cheese: FetaFondue – the guild addon for WoW Forever

<p align="center"><img src="assets/logo.png" alt="FetaFondue" width="300"></p>

Shows what the guild can craft, who is online, upcoming raids, guild achievements and what your guildmates wear, and warns you when a player on the guild's shitlist joins your group. Everybody who installs it shares a little info, so the more people use it, the better it gets.

**Install – automatic (WowUp, updates itself)**
1. Install WowUp from [wowup.io](https://wowup.io/#editions).
2. WowUp normally finds your WoW editions by itself, so just select the Forever client. If it is not listed, open **Options** > **WoW Clients** and click **Re-Scan**, or **Add New** and pick the game executable inside `World of Warcraft\_forever_`.
3. Click **Get Addons** > **Install from URL**, paste `https://github.com/guild-fetafondue/FetaFondue` and install.
4. Done. WowUp now installs every new version for you (right click FetaFondue in **My Addons** to check that auto update is on).

**Install – manual**
1. Download the latest `FetaFondue-x.y.z.zip` from [Releases](https://github.com/guild-fetafondue/FetaFondue/releases) and unzip it. You get a folder called `FetaFondue`.
2. Copy it into `World of Warcraft\_forever_\Interface\AddOns\` (create `Interface` / `AddOns` if missing).
3. Check that `AddOns\FetaFondue\FetaFondue.toc` exists (not `FetaFondue\FetaFondue\...`).
4. At the character screen click **AddOns**, tick **FetaFondue** (and **Load out of date AddOns** if needed).
5. In game click the cheese on the minimap, or type `/ff`.

**First-time setup (once per character)**
Open each of your professions and wait 1-2 seconds on each (Mining = Smelting window). Then open the character panel (`C`) and talents (`N`).

**What you get**
- **Dashboard:** guild totals and bank gold, upcoming raids with sign-ups, members, requests, who is online (click a name to see gear, talents and alts)
- **Sweatshop:** recipes the guild can craft with a Request button, plus the guild's profession specializations and cooldowns
- **Analytics:** levels, classes, races, specs, roles, professions and recipes
- **Achievements:** guild firsts (level 60, maxed professions, raid clears)
- **Events:** the raid calendar, with a reminder 15 minutes before a raid you signed up for
- **Shitlist:** officers add and remove names, everybody gets a warning when a listed player joins their party. Guild invites are checked too: the invite button refuses a listed name, an invite sent the normal way in game shows a warning
- **Management** (officers only): shared officer notes, managing the shitlist, raid scheduling from Raid-Helper, and guild / raid invites

**Optional but recommended:** the addon **Profession Master**. With it, FetaFondue can show the skill level every recipe needs. One person having it is enough, the numbers are shared in the guild.

**Shared with the guild:** professions, recipes, requests, counters, gear and talents. **Never shared:** chat, bags, gold on hand.
**Issues?** Type `/ff probe` and send the output to an officer along with an explanation of the situation.
