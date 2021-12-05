/-
Copyright (c) 2021 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Gabriel Ebner
-/
import Lean

/-!
Defines term syntax to call unsafe functions.

```
def cool :=
  unsafe (unsafeCast () : Nat)

#eval cool
```
-/

namespace Mathlib.TermUnsafe
open Lean Meta Elab Term

def mkAuxName (hint : Name) : TermElabM Name :=
  withFreshMacroScope do
    let name := (← getDeclName?).getD Name.anonymous ++ hint
    addMacroScope (← getMainModule) name (← getCurrMacroScope)

syntax "unsafe " term : term

elab_rules : term <= expectedType
  | `(unsafe ?$mvar) => do
    let t ← elabTerm (← `(?$mvar)) none
    let t ← instantiateMVars t
    let t ← if !t.hasExprMVar then t else
      tryPostpone
      synthesizeSyntheticMVarsNoPostponing
      instantiateMVars t
    if ← logUnassignedUsingErrorInfos (← getMVars t) then throwAbortTerm
    let t ← mkAuxDefinitionFor (← mkAuxName `unsafe) t
    let Expr.const unsafeFn unsafeLvls .. ← t.getAppFn | unreachable!
    let ConstantInfo.defnInfo unsafeDefn ← getConstInfo unsafeFn | unreachable!
    let implName ← mkAuxName `impl
    addDecl <| Declaration.defnDecl {
      name := implName
      type := unsafeDefn.type
      levelParams := unsafeDefn.levelParams
      value := (← mkArbitrary unsafeDefn.type)
      hints := ReducibilityHints.opaque
      safety := DefinitionSafety.safe
    }
    setImplementedBy implName unsafeFn
    mkAppN (mkConst implName unsafeLvls) t.getAppArgs
  | `(unsafe $t) => do
    let m ← elabTerm (← `(?m)) expectedType
    assignExprMVar m.mvarId! (← elabTerm t expectedType)
    elabTerm (← `(unsafe ?m)) expectedType
