import 'package:flutter/material.dart';

class ContractorCompany {
  final String name;
  final String role;
  final String projectCount;
  final Color color;

  const ContractorCompany({
    required this.name,
    required this.role,
    required this.projectCount,
    required this.color,
  });
}

const allCompaniesLabel = "All Companies";

final contractorModeController = ValueNotifier<bool>(false);

const contractorCompanies = [
  ContractorCompany(
    name: "Kittan Electric",
    role: "Distribution boards contractor",
    projectCount: "84 projects",
    color: Color(0xFFFF7A1A),
  ),
  ContractorCompany(
    name: "Voltline Panels",
    role: "Panel builder",
    projectCount: "46 projects",
    color: Color(0xFF8B4DFF),
  ),
  ContractorCompany(
    name: "Noga Controls",
    role: "Maintenance company",
    projectCount: "31 projects",
    color: Color(0xFF18D4E8),
  ),
  ContractorCompany(
    name: "Apex Switchgear",
    role: "Industrial switchboards",
    projectCount: "22 projects",
    color: Color(0xFF35E177),
  ),
];

final activeCompanyController = ValueNotifier<ContractorCompany?>(
  contractorCompanies.first,
);
