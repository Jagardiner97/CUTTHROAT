#include "cutthroatApp.h"
#include "Moose.h"
#include "AppFactory.h"
#include "ModulesApp.h"
#include "MooseSyntax.h"

InputParameters
cutthroatApp::validParams()
{
  InputParameters params = MooseApp::validParams();
  params.set<bool>("use_legacy_material_output") = false;
  params.set<bool>("use_legacy_initial_residual_evaluation_behavior") = false;
  return params;
}

cutthroatApp::cutthroatApp(const InputParameters & parameters) : MooseApp(parameters)
{
  cutthroatApp::registerAll(_factory, _action_factory, _syntax);
}

cutthroatApp::~cutthroatApp() {}

void
cutthroatApp::registerAll(Factory & f, ActionFactory & af, Syntax & syntax)
{
  ModulesApp::registerAllObjects<cutthroatApp>(f, af, syntax);
  Registry::registerObjectsTo(f, {"cutthroatApp"});
  Registry::registerActionsTo(af, {"cutthroatApp"});

  /* register custom execute flags, action syntax, etc. here */
}

void
cutthroatApp::registerApps()
{
  registerApp(cutthroatApp);
}

/***************************************************************************************************
 *********************** Dynamic Library Entry Points - DO NOT MODIFY ******************************
 **************************************************************************************************/
extern "C" void
cutthroatApp__registerAll(Factory & f, ActionFactory & af, Syntax & s)
{
  cutthroatApp::registerAll(f, af, s);
}
extern "C" void
cutthroatApp__registerApps()
{
  cutthroatApp::registerApps();
}
