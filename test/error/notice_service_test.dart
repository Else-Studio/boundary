import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sut_factory.dart';

void main() {
  late NoticeService notices;

  setUp(() {
    notices = SutFactory.createNoticeService();
  });

  tearDown(() {
    try {
      notices.dispose();
    } catch (_) {}
  });

  test('show reaches only listeners that subscribed before the notice', () async {
    notices.show(const Notice('a'));

    final first = <Notice>[];
    final firstSub = notices.notices.listen(first.add);
    addTearDown(() async {
      try {
        await firstSub.cancel();
      } catch (_) {}
    });

    final second = <Notice>[];
    final secondSub = notices.notices.listen(second.add);
    addTearDown(() async {
      try {
        await secondSub.cancel();
      } catch (_) {}
    });

    notices.show(const Notice('b', level: NoticeLevel.success));
    await pumpEventQueue();

    expect(first, [const Notice('b', level: NoticeLevel.success)]);
    expect(second, [const Notice('b', level: NoticeLevel.success)]);
  });
}
