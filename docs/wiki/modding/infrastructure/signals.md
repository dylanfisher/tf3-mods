---
title: Signals
page_id: modding:infrastructure:signals
source: https://wiki.transportfever3.com/doku.php?id=modding:infrastructure:signals
---

# Signals

Signals are [edge objects](../../modding/constructions/types.md#edge_objects) that can be attached to tracks.

For the visual representation, they have a special set of event data for animations too.

## Events

![](../../_media/modding/infrastructure/signals.gif)  
signal animations

Especially for signals the [animation events](../../modding/general/resourcetypes/mdl.md#animations) are an important aspect. They can be used in mesh nodes to support the visualisation of the two signalisation states 'red' and 'green':

- `forever` animation is used for any permanently looped animation.
- `idle_red` animation is used as a loop while the signal is in 'red' state.
- `green` animation is used when the signal switches from 'red' to 'green'.
- `idle_green` animation is used as a loop while the signal is in 'green' state.
- `red` animation is used when the signal switches from 'green' to 'red'.

While the `forever` animation runs constantly, the other four events form a loop. Usually a signal is in red state and the `idle_red` animation is performed. As soon as it switches to green, `green` is performed once. Then `idle_green` is looped as long as the signal stays green. When the signal turns back to red, `red` is performed once before `idle_red` is looped again.

The idle animations can be used e.g. for blinking signals.
