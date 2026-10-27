// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Member _$MemberFromJson(Map<String, dynamic> json) => _Member(
  id: json['id'] as String,
  fullName: json['full_name'] as String,
  phone: json['phone'] as String,
  email: json['email'] as String? ?? '',
  status: json['status'] as String? ?? 'active',
  address: json['address'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
  joiningDate: json['joining_date'] as String,
  assignedTrainer: json['assigned_trainer'] as String?,
);

Map<String, dynamic> _$MemberToJson(_Member instance) => <String, dynamic>{
  'id': instance.id,
  'full_name': instance.fullName,
  'phone': instance.phone,
  'email': instance.email,
  'status': instance.status,
  'address': instance.address,
  'notes': instance.notes,
  'joining_date': instance.joiningDate,
  'assigned_trainer': instance.assignedTrainer,
};
