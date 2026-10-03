---
title: Playlists
page_id: modding:misc:playlists
source: https://wiki.transportfever3.com/doku.php?id=modding:misc:playlists
---

# Playlists

Playlists allow to create a list of music tracks that the game can play in the background while playing.  
The configuration of playlists is defined in a `.plist.lua` file. The script needs to have a `data()` function that returns a struct like this:

```lua
function data()
return {
  name = _("Transport Fever 3"),
  tracks = {
    {
      name = "J.J. Ipsen - A Promise Made Is a Promise Kept",
      fileName = "a_promise_made_is_a_promise_kept.ogg",
    },
    {
      name = "J.J. Ipsen - Cup of Joe",
      fileName = "cup_of_joe.ogg",
    },
    {
      name = "J.J. Ipsen - Unforeseen Circumstances",
      fileName = "unforeseen_circumstances.ogg",
    },
      ...
  },
  order = 1,
}
end
```

The playlist struct has three properties:

- `name` the display name of the playlist used in the games settings menu
- `tracks` a list of track structs

  - `name` the display name of the track used in the music player
  - `fileName` reference to an audio file relative to the playlist configuration file
- `order` determines the position in the playlist selection in the games settings

Playlists can be selected in the Audio tab of the settings.
