import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chat/core/cache/lru_cache.dart';

void main() {
  group('LRUCache', () {
    group('basic operations', () {
      test('put and get returns correct value', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);

        expect(cache.get('a'), equals(1));
        expect(cache.get('b'), equals(2));
        expect(cache.get('c'), equals(3));
      });

      test('get returns null for missing key', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        expect(cache.get('missing'), isNull);
      });

      test('put updates existing key', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('a', 10);

        expect(cache.get('a'), equals(10));
        expect(cache.length, equals(1));
      });

      test('remove removes item from cache', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        final removed = cache.remove('a');

        expect(removed, equals(1));
        expect(cache.get('a'), isNull);
        expect(cache.length, equals(0));
      });

      test('remove returns null for missing key', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        expect(cache.remove('missing'), isNull);
      });

      test('containsKey returns correct value', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);

        expect(cache.containsKey('a'), isTrue);
        expect(cache.containsKey('b'), isFalse);
      });

      test('clear removes all items', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('b', 2);
        cache.clear();

        expect(cache.isEmpty, isTrue);
        expect(cache.length, equals(0));
      });
    });

    group('eviction', () {
      test('evicts oldest item when maxSize exceeded', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);
        cache.put('d', 4); // Should evict 'a'

        expect(cache.get('a'), isNull);
        expect(cache.get('b'), equals(2));
        expect(cache.get('c'), equals(3));
        expect(cache.get('d'), equals(4));
        expect(cache.length, equals(3));
      });

      test('accessing item makes it most recently used', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);

        cache.get('a'); // Access 'a', making it most recent

        cache.put('d', 4); // Should evict 'b' (now oldest)

        expect(cache.get('a'), equals(1)); // 'a' should still exist
        expect(cache.get('b'), isNull); // 'b' should be evicted
        expect(cache.get('c'), equals(3));
        expect(cache.get('d'), equals(4));
      });

      test('onEvict callback is called when item is evicted', () {
        final evictedItems = <String>[];
        final cache = LRUCache<String, int>(
          maxSize: 2,
          onEvict: (key, value) => evictedItems.add(key),
        );

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3); // Evicts 'a'

        expect(evictedItems, contains('a'));
        expect(evictedItems.length, equals(1));
      });

      test('onEvict is called for all items on clear', () {
        final evictedItems = <String>[];
        final cache = LRUCache<String, int>(
          maxSize: 3,
          onEvict: (key, value) => evictedItems.add(key),
        );

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);
        cache.clear();

        expect(evictedItems.length, equals(3));
        expect(evictedItems, containsAll(['a', 'b', 'c']));
      });
    });

    group('properties', () {
      test('length returns correct count', () {
        final cache = LRUCache<String, int>(maxSize: 5);

        expect(cache.length, equals(0));

        cache.put('a', 1);
        expect(cache.length, equals(1));

        cache.put('b', 2);
        expect(cache.length, equals(2));
      });

      test('isEmpty and isNotEmpty work correctly', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        expect(cache.isEmpty, isTrue);
        expect(cache.isNotEmpty, isFalse);

        cache.put('a', 1);

        expect(cache.isEmpty, isFalse);
        expect(cache.isNotEmpty, isTrue);
      });

      test('keys returns all keys in order', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);

        expect(cache.keys.toList(), equals(['a', 'b', 'c']));
      });

      test('values returns all values in order', () {
        final cache = LRUCache<String, int>(maxSize: 3);

        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);

        expect(cache.values.toList(), equals([1, 2, 3]));
      });
    });
  });

  group('SizedLRUCache', () {
    group('basic operations', () {
      test('put and get returns correct value', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        cache.put('a', data);

        expect(cache.get('a'), equals(data));
      });

      test('get returns null for missing key', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        expect(cache.get('missing'), isNull);
      });

      test('put updates existing key', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6, 7, 8]);

        cache.put('a', data1);
        expect(cache.currentSizeBytes, equals(3));

        cache.put('a', data2);
        expect(cache.currentSizeBytes, equals(5));
        expect(cache.get('a'), equals(data2));
      });

      test('remove removes item and updates size', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        cache.put('a', data);

        expect(cache.currentSizeBytes, equals(5));

        cache.remove('a');

        expect(cache.currentSizeBytes, equals(0));
        expect(cache.get('a'), isNull);
      });

      test('clear resets size to zero', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        cache.put('a', Uint8List.fromList([1, 2, 3]));
        cache.put('b', Uint8List.fromList([4, 5, 6, 7]));

        expect(cache.currentSizeBytes, equals(7));

        cache.clear();

        expect(cache.currentSizeBytes, equals(0));
        expect(cache.length, equals(0));
      });
    });

    group('size-based eviction', () {
      test('evicts oldest items when size exceeded', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 10,
          sizeCalculator: (bytes) => bytes.length,
        );

        cache.put('a', Uint8List.fromList([1, 2, 3])); // 3 bytes
        cache.put('b', Uint8List.fromList([4, 5, 6])); // 3 bytes
        cache.put('c', Uint8List.fromList([7, 8, 9, 10, 11])); // 5 bytes, evicts 'a'

        expect(cache.get('a'), isNull);
        expect(cache.get('b'), isNotNull);
        expect(cache.get('c'), isNotNull);
        expect(cache.currentSizeBytes, equals(8));
      });

      test('accessing item makes it most recently used', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 10,
          sizeCalculator: (bytes) => bytes.length,
        );

        cache.put('a', Uint8List.fromList([1, 2, 3])); // 3 bytes
        cache.put('b', Uint8List.fromList([4, 5, 6])); // 3 bytes

        cache.get('a'); // Access 'a', making it most recent

        cache.put('c', Uint8List.fromList([7, 8, 9, 10, 11])); // 5 bytes, evicts 'b'

        expect(cache.get('a'), isNotNull);
        expect(cache.get('b'), isNull);
        expect(cache.get('c'), isNotNull);
      });

      test('rejects item larger than maxSize', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 5,
          sizeCalculator: (bytes) => bytes.length,
        );

        cache.put('large', Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));

        expect(cache.get('large'), isNull);
        expect(cache.currentSizeBytes, equals(0));
      });

      test('onEvict callback is called when item is evicted', () {
        final evictedItems = <String>[];
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 5,
          sizeCalculator: (bytes) => bytes.length,
          onEvict: (key, value) => evictedItems.add(key),
        );

        cache.put('a', Uint8List.fromList([1, 2, 3]));
        cache.put('b', Uint8List.fromList([4, 5, 6])); // Evicts 'a'

        expect(evictedItems, contains('a'));
      });
    });

    group('properties', () {
      test('currentSizeBytes tracks total size', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        expect(cache.currentSizeBytes, equals(0));

        cache.put('a', Uint8List.fromList([1, 2, 3]));
        expect(cache.currentSizeBytes, equals(3));

        cache.put('b', Uint8List.fromList([4, 5, 6, 7]));
        expect(cache.currentSizeBytes, equals(7));
      });

      test('usageRatio calculates correctly', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        expect(cache.usageRatio, equals(0.0));

        cache.put('a', Uint8List.fromList(List.filled(50, 0)));
        expect(cache.usageRatio, equals(0.5));

        cache.put('b', Uint8List.fromList(List.filled(25, 0)));
        expect(cache.usageRatio, equals(0.75));
      });

      test('maxSize returns maxSizeBytes', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 100,
          sizeCalculator: (bytes) => bytes.length,
        );

        expect(cache.maxSize, equals(100));
      });
    });

    group('memory limit compliance', () {
      test('respects 50MB memory limit', () {
        final cache = SizedLRUCache<String, Uint8List>(
          maxSizeBytes: 50 * 1024 * 1024, // 50MB
          sizeCalculator: (bytes) => bytes.length,
        );

        // Add items totaling 60MB
        for (int i = 0; i < 6; i++) {
          cache.put('item$i', Uint8List(10 * 1024 * 1024)); // 10MB each
        }

        // Should have evicted some items to stay under 50MB
        expect(cache.currentSizeBytes, lessThanOrEqualTo(50 * 1024 * 1024));
      });
    });
  });
}
