import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database.dart';
import '../../core/operation_error.dart';
import '../../core/record_labels.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/workspace_repository.dart';
import '../payments/domain/money.dart';
import 'data/operations_repository.dart';

Future<void> showPlanChange(BuildContext context,CachedRecord subscription) async {
  final repo=context.read<WorkspaceRepository>();
  if(!repo.access.finances)return;
  final operations=context.read<OperationsRepository>(),sync=context.read<SyncEngine>();
  final plans=await repo.watch('membership_packages').first;
  if(!context.mounted)return;
  final result=await showDialog<Map<String,dynamic>>(context:context,barrierDismissible:false,
    builder:(_)=>PlanChangeDialog(subscription:subscription,plans:plans,operations:operations,scope:repo.scope));
  if(result==null)return;
  try {await sync.sync();}catch(_){}
  if(!context.mounted)return;
  final q=result['quote'] as Map?;
  final message=q==null?'Plan scheduled for the next renewal. Open Invoices to review the balance.':
    (q['additional_payment_minor'] as int? ?? 0)>0
      ? 'Plan updated. Additional payment due: ${Money.format(q['additional_payment_minor'] as int,q['currency'] as String)}. Open the invoice to record payment.'
      : 'Plan updated. Member credit available: ${Money.format(result['member_credit_minor'] as int? ?? 0,q['currency'] as String)}.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
}

class PlanChangeDialog extends StatefulWidget {
  const PlanChangeDialog({super.key,required this.subscription,required this.plans,required this.operations,required this.scope});
  final CachedRecord subscription;
  final List<CachedRecord> plans;
  final OperationsRepository operations;
  final String scope;
  @override
  State<PlanChangeDialog> createState()=>_PlanChangeDialogState();
}
class _PlanChangeDialogState extends State<PlanChangeDialog> {
  final form=GlobalKey<FormState>();
  final reason=TextEditingController();
  String policy='immediate',operation=const Uuid().v4();
  String? package,error;
  Map<String,dynamic>? quote;
  bool loading=true,quoting=false,busy=false,attempted=false,mustRefresh=false;
  int generation=0;
  String get storageKey=>'gympro_plan_change:${widget.scope}:${widget.subscription.id}';
  @override
  void initState(){super.initState();unawaited(restore());}
  Future<void> restore() async {
    try {
      final prefs=await SharedPreferences.getInstance();
      final pending=prefs.getString(storageKey);
      if(!mounted)return;
      if(pending!=null){
        final data=jsonDecode(pending) as Map;
        quote=Map<String,dynamic>.from(data['quote'] as Map);
        package=data['package'] as String;operation=data['operation'] as String;reason.text=data['reason'] as String;
        attempted=true;error='A previous plan change needs confirmation. Retry the same request safely.';
      }
    }catch(_){error='Unable to load the plan change. Close and try again.';mustRefresh=true;}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> review() async {
    final ticket=++generation;
    if(policy!='immediate'||package==null){setState((){quote=null;quoting=false;error=null;});return;}
    setState((){quoting=true;quote=null;error=null;});
    try {
      final value=await widget.operations.planChangeQuote(widget.subscription.id,package!);
      if(mounted&&ticket==generation)setState((){quote=value;quoting=false;});
    }catch(failure){if(mounted&&ticket==generation)setState((){error=operationErrorMessage(failure);quoting=false;});}
  }
  Future<void> submit() async {
    if(!form.currentState!.validate()||busy||mustRefresh)return;
    if(policy=='immediate'&&(quote==null||quote!['requires_admin']==true))return;
    setState((){busy=true;attempted=true;error=null;});
    try {
      if(policy=='next_renewal'){
        await widget.operations.changePackage(widget.subscription.id,widget.subscription.version,package!,policy,reason.text.trim(),operation);
        if(mounted)Navigator.pop(context,<String,dynamic>{'scheduled':true});
        return;
      }
      final prefs=await SharedPreferences.getInstance();
      if(!await prefs.setString(storageKey,jsonEncode({'quote':quote,'package':package,'reason':reason.text.trim(),'operation':operation}))){
        throw StateError('Unable to save the plan change request. Try again.');
      }
      final result=await widget.operations.applyPlanChange(widget.subscription.id,package!,quote!,reason.text.trim(),operation);
      try {await prefs.remove(storageKey);}catch(_){}
      if(mounted)Navigator.pop(context,result);
    }catch(failure){
      if(definitiveOperationError(failure)){
        mustRefresh=true;
        try {final prefs=await SharedPreferences.getInstance();await prefs.remove(storageKey);}catch(_){}
      }
      if(mounted)setState((){busy=false;error=operationErrorMessage(failure);});
    }
  }
  @override
  void dispose(){reason.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final current=jsonDecode(widget.subscription.payload) as Map;
    final choices=widget.plans.where((p){final data=jsonDecode(p.payload) as Map;return data['status']=='active'&&p.syncState=='synced'&&p.id!=current['package_id'];}).toList();
    final q=quote;
    String money(String key)=>Money.format(q?[key] as int? ?? 0,q?['currency'] as String? ?? 'AED');
    Widget line(String label,String value,{bool bold=false})=>Padding(padding:const EdgeInsets.symmetric(vertical:5),
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(label)),const SizedBox(width:12),
        Flexible(child:Text(value,textAlign:TextAlign.right,style:TextStyle(fontWeight:bold?FontWeight.w700:FontWeight.w400)))]));
    return PopScope(canPop:!busy,child:AlertDialog(title:const Text('Change membership plan'),
      content:SizedBox(width:500,child:SingleChildScrollView(child:Form(key:form,child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('Current plan: ${(current['package_snapshot'] as Map?)?['name']??'Membership'}'),
          const SizedBox(height:16),
          if(loading)const Center(child:CircularProgressIndicator())
          else if(attempted)Text('New plan: ${q?['new_plan_name']??package}')
          else DropdownButtonFormField<String>(initialValue:package,decoration:const InputDecoration(labelText:'New plan'),
            items:[for(final plan in choices)DropdownMenuItem(value:plan.id,child:Text((jsonDecode(plan.payload) as Map)['name'] as String))],
            onChanged:(value){package=value;unawaited(review());},validator:(value)=>value==null?'Choose a new plan':null),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(initialValue:policy,decoration:const InputDecoration(labelText:'When should it change?'),
            items:const [DropdownMenuItem(value:'immediate',child:Text('Immediately — calculate the difference')),
              DropdownMenuItem(value:'next_renewal',child:Text('At the next renewal'))],
            onChanged:attempted||loading?null:(value){policy=value!;unawaited(review());}),
          const SizedBox(height:12),
          if(policy=='next_renewal')const Text('The current plan stays until it ends. A scheduled membership and invoice will be created, using any available member credit.'),
          if(quoting)const Center(child:CircularProgressIndicator()),
          if(q!=null&&policy=='immediate')Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(
            crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Text('${q['old_plan_name']} → ${q['new_plan_name']}',style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:6),Text('${q['remaining_days']} days remaining. Expiry stays ${displayDate(DateTime.parse(q['end_exclusive'] as String).subtract(const Duration(days:1)))}. Enrollment fees are not charged again.'),
              const Divider(),
              line('Unused old plan value (with tax)',Money.format((q['old_unused_minor'] as int)+(q['old_tax_minor'] as int),q['currency'] as String)),
              line('New plan for the remaining days (with tax)',Money.format((q['new_unused_minor'] as int)+(q['new_tax_minor'] as int),q['currency'] as String)),
              if((q['delta_minor'] as int)>=0)...[
                line('Additional charge',money('delta_minor')),
                line('Member credit applied',money('credit_applied_minor')),
                line('Additional payment due',money('additional_payment_minor'),bold:true),
              ]else...[
                line('Plan change credit',Money.format(-(q['delta_minor'] as int),q['currency'] as String)),
                line('Credit used for unpaid invoices',money('credit_applied_minor')),
                line('Member credit carried forward',money('member_credit_after_minor'),bold:true),
              ],
              if(q['requires_admin']==true)const Text('An administrator must approve this downgrade credit.'),
            ]))),
          const SizedBox(height:12),
          TextFormField(controller:reason,enabled:!attempted,decoration:const InputDecoration(labelText:'Reason'),
            validator:(value)=>value?.trim().isNotEmpty==true?null:'Enter a reason'),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!)),
        ])))),
      actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('Close')),
        FilledButton.icon(onPressed:loading||quoting||busy||mustRefresh||package==null||(policy=='immediate'&&(q==null||q['requires_admin']==true))?null:submit,
          icon:const Icon(CupertinoIcons.arrow_2_squarepath,size:18),label:Text(busy?'Saving…':attempted?'Retry request':'Confirm plan change'))],
    ));
  }
}
