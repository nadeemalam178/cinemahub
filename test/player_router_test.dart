import 'package:cinemahub/core/streaming/models/stream_source.dart';
import 'package:cinemahub/core/streaming/player/player_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const router = PlayerRouter();

  group('PlayerRouter.route', () {
    test('routes magnet & infoHash torrents to nativePlayer', () {
      const magnet = StreamSource(
        id: 't1',
        provider: 'Torrentio',
        name: '1080p Torrent',
        url: 'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        type: StreamType.magnet,
        isPlayableInternally: true,
      );
      expect(router.route(magnet).player, TargetPlayer.nativePlayer);

      const hashOnly = StreamSource(
        id: 't2',
        provider: 'Comet',
        name: 'Hash Only',
        url: '',
        infoHash: 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        type: StreamType.magnet,
        isPlayableInternally: true,
      );
      expect(router.route(hashOnly).player, TargetPlayer.nativePlayer);
    });

    test('routes FMHY embeds to ad-blocked webPlayer', () {
      const embed = StreamSource(
        id: 'e1',
        provider: 'FMHY / VidSrc PRO',
        name: 'VidSrc PRO',
        url: 'https://vidsrc.to/embed/movie/550',
        type: StreamType.embed,
        isPlayableInternally: true,
        metadata: {'isWebEmbed': true},
      );
      expect(router.route(embed).player, TargetPlayer.webPlayer);
    });

    test('routes HLS, DASH, and direct MP4 to nativePlayer', () {
      const hls = StreamSource(
        id: 'h1',
        provider: 'Direct',
        name: 'HLS',
        url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        type: StreamType.hls,
        isPlayableInternally: true,
      );
      expect(router.route(hls).player, TargetPlayer.nativePlayer);

      const mp4 = StreamSource(
        id: 'm1',
        provider: 'Real-Debrid',
        name: 'MP4',
        url: 'https://vjs.zencdn.net/v/oceans.mp4',
        type: StreamType.directHttp,
        isPlayableInternally: true,
      );
      expect(router.route(mp4).player, TargetPlayer.nativePlayer);
    });

    test('routes website portals to externalBrowser and empty URLs to unsupported', () {
      const site = StreamSource(
        id: 'w1',
        provider: 'FMHY',
        name: 'Directory',
        url: 'https://fmhy.net/video',
        type: StreamType.website,
        isPlayableInternally: false,
      );
      expect(router.route(site).player, TargetPlayer.externalBrowser);

      const empty = StreamSource(
        id: 'u1',
        provider: 'Broken',
        name: 'Empty',
        url: '',
        type: StreamType.hls,
        isPlayableInternally: true,
      );
      expect(router.route(empty).player, TargetPlayer.unsupported);
    });
  });
}
