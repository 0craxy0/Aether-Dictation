# dictation

Read-aloud for Roblox UIs. Point at a label for three seconds and it is read out.
A bar grows out of the middle of that text toward both edges while you wait, so
the delay is visible instead of feeling broken.

One file, no dependencies, no framework, no server.

```lua
local Dictation = loadstring(game:HttpGet("https://raw.githubusercontent.com/0craxy0/Aether-Dictation/main/dictation.lua"))()
local d = Dictation.mount()
```

That builds its own `ScreenGui`, shows the first-run card, and starts watching
every label on screen. Drop it over any UI — it only reads, it never touches
layout, and it adds nothing to the widgets it reads.

## behaviour

- **Three seconds of hover** on the same label reads it. Moving off, or onto
  another label, cancels and restarts.
- The **bar starts at the middle** of the text and reaches both edges exactly
  when the three seconds do.
- The underline is **as wide as the text**, not as wide as the label, so a short
  word in a wide row gets a short underline.
- The **first-run card** asks once:
  - **Enable** is remembered whether or not *Don't show this again* is ticked.
  - **Not now** is only remembered when the checkbox is ticked.
  - A UI that is already enabled is never asked again.
- Only one underline exists at a time and it lives above the UI, so hovering
  never resizes a label. That matters for anything using `AutomaticSize`.

## voice

A Roblox client script has no speech synthesiser. `Sound` plays `rbxassetid://`
assets or the handful of built-in `rbxasset://` sounds, and there is no API that
turns text into audio. So "text to speech" inside Roblox is really one of these:

| Approach | What it buys | What it costs |
|---|---|---|
| Default blip (built in) | Audible confirmation of what was picked up | Not speech |
| `opts.speak` with **recorded phrases** | Real speech for a fixed set of labels | You record/upload one audio asset per phrase and map it |
| `opts.speak` with an external service | Real speech, arbitrary text | Roblox cannot play an arbitrary URL, so the audio still has to reach the client as an asset |

The practical version for a UI with a known set of labels is the second row:

```lua
local VOICE = {
	["Counter projectile gravity"] = "rbxassetid://0000000000",
	["Read text aloud"] = "rbxassetid://0000000000",
}

local d = Dictation.mount({
	speak = function(text)
		local id = VOICE[text]
		if not id then return end          -- unknown phrase: stay quiet
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = 0.35
		s.Parent = game:GetService("SoundService")
		s:Play()
		s.Ended:Once(function() s:Destroy() end)
	end,
})
```

Generate the audio with any TTS tool (`say` on macOS, ElevenLabs, Google Cloud
TTS), upload the files to Roblox as audio assets, and put the ids in the map. Your
own uploads play for you without a permission prompt.

## options

Everything is optional.

| key | default | |
|---|---|---|
| `hold` | `3` | seconds of hover before it speaks |
| `thickness` | `1.5` | underline height in pixels |
| `scan` | `0.08` | how often the pointer is re-tested |
| `promptOnFirstRun` | `true` | show the card on mount |
| `speak` | `nil` | `function(text)`; nil uses the built-in blip |
| `state` | `nil` | `{ get = function(key), set = function(key, value) }` for persistence |
| `accent` `text` `muted` `panel` `raised` `stroke` `bg` | dark theme | colours |
| `font` / `fontBold` | `Gotham` | fonts |
| `name` | `"Dictation"` | ScreenGui name |
| `topLayer` | `true` | parent to `gethui()` / CoreGui when available |

## api

```lua
d.setEnabled(true)   -- also persists "enabled" when opts.state is supplied
d.toggle()
d.speak("anything")  -- reads a string directly, same pipeline as a hover
d.prompt()           -- show the card now (no-op if already enabled or answered)
d.enabled            -- current state
d.destroy()          -- disconnect and remove the ScreenGui
```

## persistence

Wire `state` to whatever you already have — a config file, a profile, an attribute:

```lua
local d = Dictation.mount({
	state = {
		get = function(key)
			if isfile("dictation.json") then
				local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile("dictation.json")) end)
				if ok and type(data) == "table" then return data[key] end
			end
		end,
		set = function(key, value)
			local data = {}
			if isfile("dictation.json") then
				local ok, old = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile("dictation.json")) end)
				if ok and type(old) == "table" then data = old end
			end
			data[key] = value
			pcall(writefile, "dictation.json", game:GetService("HttpService"):JSONEncode(data))
		end,
	},
})
```

Keys used: `enabled`, `promptDone`.

## notes

- Text under the pointer is chosen from a cached list of on-screen labels,
  re-swept once a second, so a page switch or a dropdown needs no notification.
- `TextBox` is deliberately excluded: it holds half-typed input, not a label.
- Labels using `TextScaled` are underlined across their full width, because the
  glyph width cannot be measured from `TextSize` alone.
- Labelled elements the module cannot see (hidden by an ancestor's `Visible`)
  are skipped rather than read from behind a closed page.
- No remote calls, no `loadstring` of anything but this file, nothing written to
  disk unless you supply `state`.

This is the standalone build of the read-aloud feature in
[Aether](https://github.com/0craxy0/Aether), where it is vendored as
`tail/tts.lua` so the loader keeps a single pinned origin.
