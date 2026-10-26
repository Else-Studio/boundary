# Child controllers

A page can be split into parts that each have their own logic: a search box, a detail pane, a note editor. Each part can have its own child controller, owned by the page's controller. This page shows the two ways to own a child, how to build one, how a child talks to its parent, and how a view reaches a child.

## When to use a child

Use a child controller when a part of the page has its own actions and state, and the page's controller would otherwise grow large. A child also helps when the part is reused on several pages, or when the part belongs to a key that changes, like the editor for the selected case.

A part that only displays the parent's state does not need a child. Give it the data through its constructor, or let it read the parent's controller.

## Two ways to own a child

| | `adopt(child)` | `slot<K, C>(create)` |
|---|---|---|
| How many | One child, for the parent's whole life | Zero or one child at a time, chosen by a key |
| Created | By you, before `adopt` | By the slot, when you call `activate(key)` |
| Disposed | With the parent | When the slot switches to another key, is cleared, or the parent is disposed |
| Typical use | A search box, a filter panel | A detail pane for the selected id |

Both make the parent the child's parent. A controller can have only one parent: adopting a child that already has one throws a `StateError`.

## Adopting a child

The parent takes the child in its constructor, adopts it, and listens to its events:

```dart
class CaseListController extends Controller<CaseListAction> {
  CaseListController(this._cases, SearchController search)
      : search = search {
    adopt(search);
    listenTo(search.queries, (text) => dispatch(Search(text)));
  }

  final CaseRepository _cases;

  /// Public so the page can provide it to the search box.
  final SearchController search;

  // streams, handleAction ...
}
```

`adopt` returns the child, so `late final _search = adopt(SearchController());` also works when the parent creates the child itself. A `late` field is created on first read, so read it in the constructor, for example in `listenTo`, to adopt it at once. Taking the child as a constructor parameter, as above, lets a test pass in its own.

## A slot for a keyed child

A slot holds the child for one key at a time. Give it a `create` function, and call `activate(key)` when the key changes:

```dart
// One note editor per case. Activating another id disposes the old one.
late final _note = slot<int, NoteController>(
  (id) => _notes.create()..dispatch(LoadNote(id)),
);

ValueStream<NoteController?> get note => _note.stream;
```

```dart
case LoadCase(:final id):
  _note.activate(id);
```

How a slot behaves:

- `activate(key)` with the current key returns the current child and does nothing else.
- With a new key, it creates the child, emits it on `stream`, and then disposes the previous child.
- `clear()` emits null, then disposes the current child.
- `stream` is a `ValueStream` that starts at null. It delivers synchronously, inside `activate` and `clear`.
- `current` and `key` give the current child and key.
- Calling `activate` after the parent is disposed throws a `StateError`.

**A slot child learns its key from an action.** There is no keyed `enter`. The `create` function dispatches an action that carries the key, as `LoadNote(id)` above does.

## Factories for children

A child usually needs services from the injector. Register one `ControllerFactory` per child type in `registerDependencies`:

```dart
addControllerFactory<NoteController>(
  injector,
  (i) => NoteController(
    i.get<CaseRepository>(),
    i.get<AppConfig>(),
    i.get<ErrorPolicy>(),
    i.get<NavigationService>(),
    i.get<Dialogs>(),
  ),
);
```

The parent takes `ControllerFactory<NoteController>` like any service, and calls `create()` for a new child each time:

```dart
controller: (i) => CaseController(
  i.get<CaseRepository>(),
  i.get<NavigationService>(),
  i.get<ControllerFactory<NoteController>>(),
),
```

In tests, build the factory by hand: `ControllerFactory(() => SutFactory.createNoteController(provider))`.

## How a child talks to its parent

A child exposes output events as streams. The parent subscribes with `listenTo`. Do not give a child a callback field that calls into its parent: a stream keeps the child independent of who uses it, and the subscription ends with the parent.

```dart
class SearchController extends Controller<SearchAction> {
  late final _queries = own(StreamController<String>.broadcast());

  /// Output event: the text to search for, debounced.
  Stream<String> get queries =>
      _queries.stream.debounceTime(const Duration(milliseconds: 300));

  @override
  void handleAction(SearchAction action) {
    switch (action) {
      case SearchChanged(:final text):
        emit(_queries, text.trim());
    }
  }
}
```

The parent turns each event into one of its own actions, so all of its work still starts in `handleAction`:

```dart
listenTo(search.queries, (text) => dispatch(Search(text)));
```

For a slot, the child changes over time. Listen to whichever child is current with `switchMap` over the slot's stream. `switchMap` drops the old child's stream when the slot switches:

```dart
listenTo(
  _detail.stream.switchMap((child) => child?.saved ?? const Stream.empty()),
  (id) => dispatch(CaseSaved(id)),
);
```

**Errors stay with the child.** An error in a child's action goes to the child's own `onError`, not the parent's. The parent hears only the events it listens to. If a child's errors should become notices, the child overrides its own `onError` and calls `ErrorPolicy.handle`.

## How a view reaches a child

**A slot child:** build it with `ControllerSlotBuilder`. It provides the current child with `Provider<C>.value`, and keys the subtree by the child, so widget state resets when the child changes. `empty` is shown when the slot holds no child.

```dart
ControllerSlotBuilder<NoteController>(
  stream: controller.note,
  builder: (context, note) => const NoteEditor(),
),
```

Inside, the child's widgets read it like any controller:

```dart
final note = context.read<NoteController>();
```

**An adopted child:** the parent exposes it as a public field, and the page provides it to the part that uses it:

```dart
Provider<SearchController>.value(
  value: controller.search,
  child: const SearchBox(),
),
```

The part then reads it with `context.read<SearchController>()` and dispatches to it directly. The view still never calls methods on a controller, only `dispatch`.

## Testing a parent with children

Test the child on its own, through its own actions and streams. Test the parent with a real child built by `SutFactory`, and drive the child through its actions, as the view would. For a slot, check that switching the key disposes the old child: `oldChild.isDisposed` is true after `activate` with a new key.
