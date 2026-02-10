import 'package:flutter/material.dart';

enum TaskStatus { todo, doing, done }

extension TaskStatusUi on TaskStatus {
  // Светлые "Excel-like" + сильная прозрачность
  Color get bubbleColor {
    switch (this) {
      case TaskStatus.todo:
        return const Color(0xFFFFC7CE).withOpacity(0.55); // светло-розовый (Excel)
      case TaskStatus.doing:
        return const Color(0xFFFFEB9C).withOpacity(0.55); // светло-жёлтый (Excel)
      case TaskStatus.done:
        return const Color(0xFFC6EFCE).withOpacity(0.55); // светло-зелёный (Excel)
    }
  }

  Color get borderColor {
    switch (this) {
      case TaskStatus.todo:
        return const Color(0xFFF8696B).withOpacity(0.45);
      case TaskStatus.doing:
        return const Color(0xFFFFC000).withOpacity(0.45);
      case TaskStatus.done:
        return const Color(0xFF63BE7B).withOpacity(0.45);
    }
  }

  Color get textColor {
    switch (this) {
      case TaskStatus.todo:
        return const Color(0xFF7A1E22);
      case TaskStatus.doing:
        return const Color(0xFF6A4E00);
      case TaskStatus.done:
        return const Color(0xFF1E5A2B);
    }
  }

  TaskStatus next() {
    switch (this) {
      case TaskStatus.todo:
        return TaskStatus.doing;
      case TaskStatus.doing:
        return TaskStatus.done;
      case TaskStatus.done:
        return TaskStatus.todo;
    }
  }
}

class TaskItem {
  final String id;
  final String text;
  final DateTime createdAt;

  TaskStatus status;
  bool isStriked;
  String folder;

  TaskItem({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.status,
    required this.isStriked,
    required this.folder,
  });
}
