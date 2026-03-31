//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html
#include "CUTTHROATTestApp.h"
#include "CUTTHROATApp.h"
#include "Moose.h"
#include "AppFactory.h"
#include "MooseSyntax.h"

InputParameters
CUTTHROATTestApp::validParams()
{
  InputParameters params = CUTTHROATApp::validParams();
  params.set<bool>("use_legacy_material_output") = false;
  params.set<bool>("use_legacy_initial_residual_evaluation_behavior") = false;
  return params;
}

CUTTHROATTestApp::CUTTHROATTestApp(const InputParameters & parameters) : MooseApp(parameters)
{
  CUTTHROATTestApp::registerAll(
      _factory, _action_factory, _syntax, getParam<bool>("allow_test_objects"));
}

CUTTHROATTestApp::~CUTTHROATTestApp() {}

void
CUTTHROATTestApp::registerAll(Factory & f, ActionFactory & af, Syntax & s, bool use_test_objs)
{
  CUTTHROATApp::registerAll(f, af, s);
  if (use_test_objs)
  {
    Registry::registerObjectsTo(f, {"CUTTHROATTestApp"});
    Registry::registerActionsTo(af, {"CUTTHROATTestApp"});
  }
}

void
CUTTHROATTestApp::registerApps()
{
  registerApp(CUTTHROATApp);
  registerApp(CUTTHROATTestApp);
}

/***************************************************************************************************
 *********************** Dynamic Library Entry Points - DO NOT MODIFY ******************************
 **************************************************************************************************/
// External entry point for dynamic application loading
extern "C" void
CUTTHROATTestApp__registerAll(Factory & f, ActionFactory & af, Syntax & s)
{
  CUTTHROATTestApp::registerAll(f, af, s);
}
extern "C" void
CUTTHROATTestApp__registerApps()
{
  CUTTHROATTestApp::registerApps();
}
