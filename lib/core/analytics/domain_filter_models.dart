part of 'analytics_models.dart';

enum AnalyticsDimension {
  menuItem('Menu Item'), menuCategory('Menu category (current)'), deal('Deal'),
  discount('Pre-Approved Discount'), deliveryArea('Delivery Area'), rider('Rider'),
  customerSegment('Customer identity segment'), supplier('Supplier'),
  expenseCategory('Expense category'), department('Department (current staff)'),
  ingredient('Raw Ingredient'), acquisition('Acquisition evidence');
  const AnalyticsDimension(this.label);
  final String label;
  bool get isOrder => index <= customerSegment.index;
}

class AnalyticsFilterOption {
  const AnalyticsFilterOption({required this.dimension, required this.id, required this.label});
  final AnalyticsDimension dimension;
  final String id, label;
}
