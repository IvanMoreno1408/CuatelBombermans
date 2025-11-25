import 'package:flutter/material.dart';
import '../services/user_lookup.dart';

class ReviewerName extends StatelessWidget {
  final String uid;
  final TextStyle? style;
  final String prefix; // p.ej. "Revisor: "

  const ReviewerName({
    super.key,
    required this.uid,
    this.style,
    this.prefix = 'Revisor: ',
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: UserLookup.instance.displayFor(uid),
      builder: (context, snap) {
        final text = snap.data ?? uid;
        return Text(
          '$prefix$text',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
