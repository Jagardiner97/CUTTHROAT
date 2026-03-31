#include "CUTTHROATApp.h"
#include "Moose.h"
#include "AppFactory.h"
#include "ModulesApp.h"
#include "MooseSyntax.h"

InputParameters
CUTTHROATApp::validParams()
{
  InputParameters params = MooseApp::validParams();
  params.set<bool>("use_legacy_material_output") = false;
  params.set<bool>("use_legacy_initial_residual_evaluation_behavior") = false;
  return params;
}

CUTTHROATApp::CUTTHROATApp(const InputParameters & parameters) : MooseApp(parameters)
{
  CUTTHROATApp::registerAll(_factory, _action_factory, _syntax);
}

CUTTHROATApp::~CUTTHROATApp() {}

void
CUTTHROATApp::registerAll(Factory & f, ActionFactory & af, Syntax & syntax)
{
  ModulesApp::registerAllObjects<CUTTHROATApp>(f, af, syntax);
  Registry::registerObjectsTo(f, {"CUTTHROATApp"});
  Registry::registerActionsTo(af, {"CUTTHROATApp"});

  /* register custom execute flags, action syntax, etc. here */
}

void
CUTTHROATApp::registerApps()
{
  registerApp(CUTTHROATApp);
}

/***************************************************************************************************
 *********************** Dynamic Library Entry Points - DO NOT MODIFY ******************************
 **************************************************************************************************/
extern "C" void
CUTTHROATApp__registerAll(Factory & f, ActionFactory & af, Syntax & s)
{
  CUTTHROATApp::registerAll(f, af, s);
}
extern "C" void
CUTTHROATApp__registerApps()
{
  CUTTHROATApp::registerApps();
}
