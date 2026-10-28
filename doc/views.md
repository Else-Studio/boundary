# Views

A view draws what its controller's streams say and dispatches the user's intents as actions. [building_with_boundary.md](building_with_boundary.md), rule 1, says what a view must not do. This page covers the Flutter mistakes that are easy to make inside those rules.

## Splitting a page into widgets

A page is usually a few section widgets. Each one reads the controller itself with `context.read<C>()`. Do not pass the controller down through constructors.

Data from a stream goes down through constructors. Do not wrap it in another `Provider.value`. A widget that takes its data as a parameter shows what it depends on, and a test can build it with plain values.

```dart
class CasePage extends StatelessWidget {
  const CasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CaseController>();
    return AsyncResultBuilder<CaseDetail>(
      stream: controller.detail,
      data: (context, detail) => Column(
        children: [
          CaseHeader(name: detail.name, code: detail.code),
          const CaseRemarks(),
        ],
      ),
    );
  }
}
```

`CaseHeader` takes plain values. `CaseRemarks` has its own stream, so it reads the controller and listens to that stream.

## Form values in a view

Do not read `form.control(key).value` inside `build()` to decide what to draw. `build()` runs again only when something it listens to changes, and a control's value is not one of those. The view keeps showing the old value.

When the choice is a rule, such as "show the school fields only for school-age children", the controller decides it and puts a `bool` on a stream. When the view only shows a value back, such as a character count, listen to the control:

```dart
ReactiveValueListenableBuilder<String>(
  formControlName: NoteFormKeys.note,
  builder: (context, control, child) =>
      Text('${control.value?.length ?? 0} characters'),
),
```

## Lists of rows

Give each row in a list a key made from its identity, such as `ValueKey(remark.id)`, or a form control's key for a row of fields. Without a key, Flutter matches rows to their old state by position. After a row is removed or moved, a text field's cursor, focus and scroll position stay at the old index and land on another row.

To keep the rows of a form list in step with the server, see [forms.md](forms.md), "Lists of rows".

## Dialogs

There are three kinds of dialog. Pick by who needs the answer:

| The dialog | How |
|---|---|
| Asks a question the controller needs, such as "Discard changes?" | A dialog service the controller calls. See [forms.md](forms.md), "Warning before leaving". |
| Collects a small input the view passes on, such as a new remark | `showDialog<T>` in the view. The dialog returns the input; the view dispatches an action with it. |
| Has its own logic, loading or saving | A modal route with its own controller. See [routing.md](routing.md). |

For a dialog that collects input, give `showDialog` its result type and close the dialog with `Navigator.pop(context, result)`. The dialog's buttons only pop. The view sends the result on:

```dart
onPressed: () async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => const RemarkDialog(),
  );
  if (text != null) controller.dispatch(AddRemark(text));
},
```

Waiting for a dialog in the view is fine. That is waiting for the user, not for the controller.

A dialog is not built below the page. `showDialog` puts it on the root navigator, so `context.read<C>()` inside it does not find the page's controller and throws. If the dialog needs the controller, read it before you open the dialog and provide it again:

```dart
final controller = context.read<CaseController>();
await showDialog<void>(
  context: context,
  builder: (_) => Provider<CaseController>.value(
    value: controller,
    child: const CaseCodeDialog(),
  ),
);
```

The same applies to bottom sheets and other overlays.

## Styling

Keep every colour, text style, size, radius and gap of the app in one theme file. Views take colours from `Theme.of(context).colorScheme`, text styles from `Theme.of(context).textTheme`, and sizes from the app's named constants. A raw `Colors.red` or `EdgeInsets.all(12)` in a view is a value nobody can change in one place, and the next screen picks a slightly different one.

Boundary does not ship a theme. Each app owns its values.
