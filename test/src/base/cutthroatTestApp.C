//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html
#include "cutthroatTestApp.h"
#include "cutthroatApp.h"
#include "Moose.h"
#include "AppFactory.h"
#include "MooseSyntax.h"

InputParameters
cutthroatTestApp::validParams()
{
  InputParameters params = cutthroatApp::validParams();
  params.set<bool>("use_legacy_material_output") = false;
  params.set<bool>("use_legacy_initial_residual_evaluation_behavior") = false;
  return params;
}

cutthroatTestApp::cutthroatTestApp(const InputParameters & parameters) : MooseApp(parameters)
{
  cutthroatTestApp::registerAll(
      _factory, _action_factory, _syntax, getParam<bool>("allow_test_objects"));
}

cutthroatTestApp::~cutthroatTestApp() {}

void
cutthroatTestApp::registerAll(Factory & f, ActionFactory & af, Syntax & s, bool use_test_objs)
{
  cutthroatApp::registerAll(f, af, s);
  if (use_test_objs)
  {
    Registry::registerObjectsTo(f, {"cutthroatTestApp"});
    Registry::registerActionsTo(af, {"cutthroatTestApp"});
  }
}

void
cutthroatTestApp::registerApps()
{
  registerApp(cutthroatApp);
  registerApp(cutthroatTestApp);
}

/***************************************************************************************************
 *********************** Dynamic Library Entry Points - DO NOT MODIFY ******************************
 **************************************************************************************************/
// External entry point for dynamic application loading
extern "C" void
cutthroatTestApp__registerAll(Factory & f, ActionFactory & af, Syntax & s)
{
  cutthroatTestApp::registerAll(f, af, s);
}
extern "C" void
cutthroatTestApp__registerApps()
{
  cutthroatTestApp::registerApps();
}
