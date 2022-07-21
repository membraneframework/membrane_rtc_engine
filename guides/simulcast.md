# Simulcast

Simulcast is a technique where a client sends multiple encodings of the same video to the server and the server is responsible for choosing and forwarding proper encoding to proper receiver (other client). The encoding selection is dynamic (i.e. SFU switches between encodings in time) and it is based on:

* receiver available bandwidth
* receiver preferences (e.g. explicit request to receive video in HD resolution instead of FHD)
* UI layout (e.g. videos being displayed in smaller video tiles will be sent in a lower resolution)

At the moment, Membrane supports only receiver preferences i.e. receiver can chose which encoding it is willing to receive. Additionally, sender can turn off/on specific encoding. Membrane RTC Engine will detect changes and switch to another available encoding.

## Turning simulcast on/off

On the client side simulcast can be enabled while adding a new track e.g.:

```ts
    // create MembraneWebRTC class instance
    // ...
    // add simulcasted track
    let trackId = webrtc.addTrack(track, stream, {}, {enabled: true, active_encodings: ["l", "m", "h"]});
```

This will add a new track that will be sent in three versions:
* original (identified as `h`)
* original scaled down by 2 (identified as `m`)
* original scaled down by 4 (identified as `l`)

You can turn off some of the encodings by excluding them from `active_encodings` list.
Encodings that are turned off might still be enabled using `enableTrackEncoding` function.

> #### Minimal required resolution {: .warning}
>
> To ensure that all encodings work, original track resolution has to be at least 1280x720.
> Otherwise, browser might not be able to scale resolution down.
> In case of browser, original track resolution can be specified in constraints
> passed to [`getUserMedia`](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) 
> or [`getDisplayMedia`](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia).

On the server side, simulcast can be configured while adding new WebRTC Endpoint by setting its `simulcast_config` option.
Remember to ensure `Rid`, `Mid` and `TWCC` extensions are used.

For example

```elixir
alias Membrane.RTC.Engine.Endpoint.WebRTC
alias Membrane.RTC.Engine.Endpoint.WebRTC.SimulcastConfig
alias Membrane.WebRTC.Extension.{Mid, Rid, TWCC}
# ...
%WebRTC{
  rtc_engine: rtc_engine,
  # ...
  webrtc_extensions: [Rid, Mid, TWCC],
  simulcast_config: %SimulcastConfig{
    enabled: true,
    default_encoding: fn %Track{simulcast_encodings: _simulcast_encodings} -> "m" end
  }
}
```

Here we turn simulcast on and choose medium encoding for each track to be forwarded to the client.

On the other hand, setting `enabled` to `false` will result in a `RuntimeError` whenever a simulcast track is offered, as it would be considered an illegal state.

## Disabling and enabling specific track encoding

After adding simulcasted track, user can disable specific encoding.
For example, to disable the highest encoding:

```ts
    // create MembraneWebRTC class instance
    // ...
    // add simulcasted track
    let trackId = webrtc.addTrack(track, stream, {}, true);
    webrtc.disableTrackEncoding(trackId, "h");
```

Disabled encoding can be turned on again using `enableTrackEncoding` function.

Membrane RTC Engine tracks encoding activity. 
Therefore, when some encoding is turned off, RTC Engine will detect this and switch to 
the highest available encoding.
When disabled encoding becomes active again, RTC Engine will switch back to it.

## Selecting encoding to receive

By default, RTC Engine will forward the highest available encoding.
However, this can be changed using `selectTrackEncoding` function.
For example, to receive the lowest resolution:

```ts
    webrtc.selectTrackEncoding(peerId, trackId, "l");
```

where `peerId` is id of peer this track belongs to.
