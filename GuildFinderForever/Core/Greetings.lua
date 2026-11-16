local _, ns = ...

-- Openers for the whisper to an ad's poster, keyed by ad language (ad.l)
-- and not in ns.L: the text goes to the reader, so it follows the language
-- their ad names, not the sender's client. Other ad languages get English.
-- player: to a player ad without an own guild; recruit: to a player ad,
-- %s = own guild; guild: to a guild ad, %s = advertised guild.
local Greetings = {}
ns.Greetings = Greetings

local Ads = ns.Ads

local TEXTS = {
	en = {
		player = "Hi! I saw your ad on Guild Finder Forever. Are you still looking for a guild?",
		recruit = "Hi! We at <%s> are still looking for new people. We saw your ad on Guild Finder Forever. Would you like to join us?",
		guild = "Hi! I saw the ad of <%s> on Guild Finder Forever and I'm interested. Do you have a moment to chat?",
	},
	de = {
		player = "Hi! Ich habe deine Anzeige im Guild Finder Forever gesehen. Suchst du noch eine Gilde?",
		recruit = "Hi! Wir bei <%s> suchen noch neue Leute. Wir haben deine Anzeige im Guild Finder Forever gesehen. Hättest du Lust, uns zu joinen?",
		guild = "Hi! Ich habe die Anzeige von <%s> im Guild Finder Forever gesehen und habe Interesse. Hast du kurz Zeit für ein Gespräch?",
	},
	fr = {
		player = "Salut ! J'ai vu ton annonce sur Guild Finder Forever. Tu cherches toujours une guilde ?",
		recruit = "Salut ! Chez <%s>, on cherche encore du monde. On a vu ton annonce sur Guild Finder Forever. Ça te dirait de nous rejoindre ?",
		guild = "Salut ! J'ai vu l'annonce de <%s> sur Guild Finder Forever et ça m'intéresse. Tu as un moment pour en discuter ?",
	},
	es = {
		player = "¡Hola! He visto tu anuncio en Guild Finder Forever. ¿Sigues buscando hermandad?",
		recruit = "¡Hola! En <%s> seguimos buscando gente nueva. Hemos visto tu anuncio en Guild Finder Forever. ¿Te gustaría unirte a nosotros?",
		guild = "¡Hola! He visto el anuncio de <%s> en Guild Finder Forever y me interesa. ¿Tienes un momento para hablar?",
	},
	it = {
		player = "Ciao! Ho visto il tuo annuncio su Guild Finder Forever. Stai ancora cercando una gilda?",
		recruit = "Ciao! Noi di <%s> cerchiamo ancora nuovi giocatori. Abbiamo visto il tuo annuncio su Guild Finder Forever. Ti andrebbe di unirti a noi?",
		guild = "Ciao! Ho visto l'annuncio di <%s> su Guild Finder Forever e mi interessa. Hai un momento per parlarne?",
	},
	pt = {
		player = "Olá! Vi seu anúncio no Guild Finder Forever. Você ainda está procurando uma guilda?",
		recruit = "Olá! Nós da <%s> ainda estamos procurando gente nova. Vimos seu anúncio no Guild Finder Forever. Você gostaria de se juntar a nós?",
		guild = "Olá! Vi o anúncio da <%s> no Guild Finder Forever e tenho interesse. Você tem um momento para conversar?",
	},
	ru = {
		player = "Привет! Я увидел твоё объявление в Guild Finder Forever. Ты ещё ищешь гильдию?",
		recruit = "Привет! Мы в <%s> ещё ищем новых игроков. Мы увидели твоё объявление в Guild Finder Forever. Хочешь к нам присоединиться?",
		guild = "Привет! Я увидел объявление гильдии <%s> в Guild Finder Forever, и мне интересно. Найдётся минутка поговорить?",
	},
}

-- Longest whisper the server takes.
Greetings.MAX_LENGTH = 255

-- Opener for a whisper to ad's poster. Nil with prefilling off (the
-- default) and for a guild ad without a name. An own message from the
-- settings replaces the built-in ones for every ad.
function Greetings.For(ad)
	local saved = ns.db and ns.db.settings
	if not (saved and saved.whisperPrefill) then
		return nil
	end
	local own = saved.whisperText
	if type(own) == "string" and own:find("%S") then
		return own
	end
	local texts = TEXTS[ad.l] or TEXTS.en
	if ad.k == Ads.KIND_GUILD then
		return ad.n and texts.guild:format(ad.n) or nil
	end
	local guild = Ads.GetGuild()
	return guild and texts.recruit:format(guild) or texts.player
end
