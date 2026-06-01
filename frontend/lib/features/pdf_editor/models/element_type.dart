import 'package:flutter/material.dart';

enum ElementType {
  text,
  image,
  table,
  logo,
  signatureBlock,
  divider;

  String get label => switch (this) {
        ElementType.text => 'Text',
        ElementType.image => 'Image',
        ElementType.table => 'Table',
        ElementType.logo => 'Logo',
        ElementType.signatureBlock => 'Signature Block',
        ElementType.divider => 'Divider',
      };

  IconData get icon => switch (this) {
        ElementType.text => Icons.text_fields,
        ElementType.image => Icons.image_outlined,
        ElementType.table => Icons.table_chart_outlined,
        ElementType.logo => Icons.business_outlined,
        ElementType.signatureBlock => Icons.draw_outlined,
        ElementType.divider => Icons.horizontal_rule,
      };

  String get jsonKey => switch (this) {
        ElementType.text => 'text',
        ElementType.image => 'image',
        ElementType.table => 'table',
        ElementType.logo => 'logo',
        ElementType.signatureBlock => 'signature_block',
        ElementType.divider => 'divider',
      };

  static ElementType fromJson(String value) => switch (value) {
        'text' => ElementType.text,
        'image' => ElementType.image,
        'table' => ElementType.table,
        'logo' => ElementType.logo,
        'signature_block' => ElementType.signatureBlock,
        'divider' => ElementType.divider,
        _ => throw ArgumentError('Unknown element type: $value'),
      };
}

enum TemplateType {
  proposal,
  contract,
  changeOrder,
  purchaseOrder,
  invoice,
  bidRequest,
  whs,
  dailyLog,
  qualityChecklist,
  lienWaiver,
  custom;

  String get label => switch (this) {
        TemplateType.proposal => 'Proposal',
        TemplateType.contract => 'Contract',
        TemplateType.changeOrder => 'Change Order',
        TemplateType.purchaseOrder => 'Purchase Order',
        TemplateType.invoice => 'Invoice',
        TemplateType.bidRequest => 'Bid Request',
        TemplateType.whs => 'WHS / Safety',
        TemplateType.dailyLog => 'Daily Log',
        TemplateType.qualityChecklist => 'Quality Checklist',
        TemplateType.lienWaiver => 'Lien Waiver',
        TemplateType.custom => 'Custom',
      };

  String get jsonKey => switch (this) {
        TemplateType.proposal => 'proposal',
        TemplateType.contract => 'contract',
        TemplateType.changeOrder => 'change_order',
        TemplateType.purchaseOrder => 'po',
        TemplateType.invoice => 'invoice',
        TemplateType.bidRequest => 'bid_request',
        TemplateType.whs => 'whs',
        TemplateType.dailyLog => 'daily_log',
        TemplateType.qualityChecklist => 'quality_checklist',
        TemplateType.lienWaiver => 'lien_waiver',
        TemplateType.custom => 'custom',
      };

  static TemplateType fromJson(String value) => switch (value) {
        'proposal' => TemplateType.proposal,
        'contract' => TemplateType.contract,
        'change_order' => TemplateType.changeOrder,
        'po' => TemplateType.purchaseOrder,
        'invoice' => TemplateType.invoice,
        'bid_request' => TemplateType.bidRequest,
        'whs' => TemplateType.whs,
        'daily_log' => TemplateType.dailyLog,
        'quality_checklist' => TemplateType.qualityChecklist,
        'lien_waiver' => TemplateType.lienWaiver,
        'custom' => TemplateType.custom,
        _ => TemplateType.custom,
      };

}
