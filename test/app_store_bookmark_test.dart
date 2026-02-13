import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:dogfinder/main.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("AppStore bookmark persistence", () {
    test("saved post ids persist across store recreation", () async {
      SharedPreferences.setMockInitialValues({});

      final store = await AppStore.create();
      await store.toggleSavedPost("post_1");

      final recreated = await AppStore.create();
      expect(recreated.isSavedPost("post_1"), isTrue);
    });

    test("toggle removes existing saved post id", () async {
      SharedPreferences.setMockInitialValues({
        "dog_finder_saved_post_ids": <String>["post_2"],
      });

      final store = await AppStore.create();
      expect(store.isSavedPost("post_2"), isTrue);

      await store.toggleSavedPost("post_2");
      expect(store.isSavedPost("post_2"), isFalse);
    });
  });
}
