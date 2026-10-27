import 'package:freezed_annotation/freezed_annotation.dart';
part 'member.freezed.dart';
part 'member.g.dart';

@freezed
abstract class Member with _$Member {
  const factory Member({
    required String id,
    @JsonKey(name: 'full_name') required String fullName,
    required String phone,
    @Default('') String email,
    @Default('active') String status,
    @Default('') String address,
    @Default('') String notes,
    @JsonKey(name: 'joining_date') required String joiningDate,
    @JsonKey(name: 'assigned_trainer') String? assignedTrainer,
  }) = _Member;
  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
}
