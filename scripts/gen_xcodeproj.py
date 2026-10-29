"""Writes I4A.xcodeproj (project.pbxproj and the shared scheme).

The project file is generated so it stays small and reviewable. Run it
after adding or removing a source file:

    python3 scripts/gen_xcodeproj.py

IDs are derived from file names, so regenerating an unchanged layout gives
an identical file.
"""
import hashlib, os, sys
root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

app_sources = sorted(f for f in os.listdir(os.path.join(root,'I4A')) if f.endswith('.swift'))
test_sources = sorted(f for f in os.listdir(os.path.join(root,'I4ATests')) if f.endswith('.swift'))

P = {}  # id -> text
def ref(name): return oid('ref:'+name)
def bf(target, name): return oid('bf:'+target+':'+name)

proj = oid('project'); main_group = oid('group:main'); app_group = oid('group:I4A'); test_group = oid('group:I4ATests'); products_group = oid('group:Products')
app_target = oid('target:I4A'); test_target = oid('target:I4ATests')
app_product = oid('product:I4A.app'); test_product = oid('product:I4ATests.xctest')
app_src_phase = oid('phase:I4A:sources'); app_fw_phase = oid('phase:I4A:frameworks'); app_res_phase = oid('phase:I4A:resources')
test_src_phase = oid('phase:I4ATests:sources'); test_fw_phase = oid('phase:I4ATests:frameworks'); test_res_phase = oid('phase:I4ATests:resources')
proj_cfg_list = oid('cfglist:project'); app_cfg_list = oid('cfglist:I4A'); test_cfg_list = oid('cfglist:I4ATests')
proj_debug = oid('cfg:project:Debug'); proj_release = oid('cfg:project:Release')
app_debug = oid('cfg:I4A:Debug'); app_release = oid('cfg:I4A:Release')
test_debug = oid('cfg:I4ATests:Debug'); test_release = oid('cfg:I4ATests:Release')
dep = oid('dependency'); proxy = oid('proxy')
assets = 'Assets.xcassets'
base_xcconfig = 'Config/Base.xcconfig'
config_group = oid('group:Config')

out = []
w = out.append
w('// !$*UTF8*$!')
w('{')
w('\tarchiveVersion = 1;')
w('\tclasses = {')
w('\t};')
w('\tobjectVersion = 56;')
w('\tobjects = {')
w('')
w('/* Begin PBXBuildFile section */')
for f in app_sources:
    w(f'\t\t{bf("I4A",f)} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref(f)} /* {f} */; }};')
w(f'\t\t{bf("I4A",assets)} /* {assets} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref(assets)} /* {assets} */; }};')
for f in test_sources:
    w(f'\t\t{bf("I4ATests",f)} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref(f)} /* {f} */; }};')
w('/* End PBXBuildFile section */')
w('')
w('/* Begin PBXContainerItemProxy section */')
w(f'\t\t{proxy} /* PBXContainerItemProxy */ = {{')
w('\t\t\tisa = PBXContainerItemProxy;')
w(f'\t\t\tcontainerPortal = {proj} /* Project object */;')
w('\t\t\tproxyType = 1;')
w(f'\t\t\tremoteGlobalIDString = {app_target};')
w('\t\t\tremoteInfo = I4A;')
w('\t\t};')
w('/* End PBXContainerItemProxy section */')
w('')
w('/* Begin PBXFileReference section */')
w(f'\t\t{app_product} /* I4A.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = I4A.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
w(f'\t\t{test_product} /* I4ATests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = I4ATests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
for f in app_sources + test_sources:
    w(f'\t\t{ref(f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};')
w(f'\t\t{ref(assets)} /* {assets} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {assets}; sourceTree = "<group>"; }};')
w(f'\t\t{ref(base_xcconfig)} /* Base.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; }};')
w('/* End PBXFileReference section */')
w('')
w('/* Begin PBXFrameworksBuildPhase section */')
for ph in (app_fw_phase, test_fw_phase):
    w(f'\t\t{ph} /* Frameworks */ = {{')
    w('\t\t\tisa = PBXFrameworksBuildPhase;')
    w('\t\t\tbuildActionMask = 2147483647;')
    w('\t\t\tfiles = (')
    w('\t\t\t);')
    w('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    w('\t\t};')
w('/* End PBXFrameworksBuildPhase section */')
w('')
w('/* Begin PBXGroup section */')
def group(gid, name, children, path=None):
    w(f'\t\t{gid}' + (f' /* {name} */' if name else '') + ' = {')
    w('\t\t\tisa = PBXGroup;')
    w('\t\t\tchildren = (')
    for cid, cname in children:
        w(f'\t\t\t\t{cid} /* {cname} */,')
    w('\t\t\t);')
    if path: w(f'\t\t\tpath = {path};')
    elif name: w(f'\t\t\tname = {name};')
    w('\t\t\tsourceTree = "<group>";')
    w('\t\t};')
group(main_group, None, [(app_group,'I4A'),(test_group,'I4ATests'),(products_group,'Products')])
group(app_group, 'I4A', [(ref(f),f) for f in app_sources] + [(ref(assets),assets), (config_group,'Config')], path='I4A')
group(config_group, 'Config', [(ref(base_xcconfig),'Base.xcconfig')], path='Config')
group(test_group, 'I4ATests', [(ref(f),f) for f in test_sources], path='I4ATests')
group(products_group, 'Products', [(app_product,'I4A.app'),(test_product,'I4ATests.xctest')])
w('/* End PBXGroup section */')
w('')
w('/* Begin PBXNativeTarget section */')
def target(tid, name, cfglist, phases, deps, product, ptype, prodname):
    w(f'\t\t{tid} /* {name} */ = {{')
    w('\t\t\tisa = PBXNativeTarget;')
    w(f'\t\t\tbuildConfigurationList = {cfglist} /* Build configuration list for PBXNativeTarget "{name}" */;')
    w('\t\t\tbuildPhases = (')
    for pid, pname in phases: w(f'\t\t\t\t{pid} /* {pname} */,')
    w('\t\t\t);')
    w('\t\t\tbuildRules = (')
    w('\t\t\t);')
    w('\t\t\tdependencies = (')
    for d in deps: w(f'\t\t\t\t{d} /* PBXTargetDependency */,')
    w('\t\t\t);')
    w(f'\t\t\tname = {name};')
    w(f'\t\t\tproductName = {name};')
    w(f'\t\t\tproductReference = {product} /* {prodname} */;')
    w(f'\t\t\tproductType = "{ptype}";')
    w('\t\t};')
target(app_target,'I4A',app_cfg_list,[(app_src_phase,'Sources'),(app_fw_phase,'Frameworks'),(app_res_phase,'Resources')],[],app_product,'com.apple.product-type.application','I4A.app')
target(test_target,'I4ATests',test_cfg_list,[(test_src_phase,'Sources'),(test_fw_phase,'Frameworks'),(test_res_phase,'Resources')],[dep],test_product,'com.apple.product-type.bundle.unit-test','I4ATests.xctest')
w('/* End PBXNativeTarget section */')
w('')
w('/* Begin PBXProject section */')
w(f'\t\t{proj} /* Project object */ = {{')
w('\t\t\tisa = PBXProject;')
w('\t\t\tattributes = {')
w('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
w('\t\t\t\tLastSwiftUpdateCheck = 1500;')
w('\t\t\t\tLastUpgradeCheck = 1500;')
w('\t\t\t\tTargetAttributes = {')
w(f'\t\t\t\t\t{app_target} = {{')
w('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;')
w('\t\t\t\t\t};')
w(f'\t\t\t\t\t{test_target} = {{')
w('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;')
w(f'\t\t\t\t\t\tTestTargetID = {app_target};')
w('\t\t\t\t\t};')
w('\t\t\t\t};')
w('\t\t\t};')
w(f'\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "I4A" */;')
w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
w('\t\t\tdevelopmentRegion = ko;')
w('\t\t\thasScannedForEncodings = 0;')
w('\t\t\tknownRegions = (')
w('\t\t\t\tko,')
w('\t\t\t\ten,')
w('\t\t\t\tBase,')
w('\t\t\t);')
w(f'\t\t\tmainGroup = {main_group};')
w(f'\t\t\tproductRefGroup = {products_group} /* Products */;')
w('\t\t\tprojectDirPath = "";')
w('\t\t\tprojectRoot = "";')
w('\t\t\ttargets = (')
w(f'\t\t\t\t{app_target} /* I4A */,')
w(f'\t\t\t\t{test_target} /* I4ATests */,')
w('\t\t\t);')
w('\t\t};')
w('/* End PBXProject section */')
w('')
w('/* Begin PBXResourcesBuildPhase section */')
for ph, files in ((app_res_phase, [(bf("I4A",assets), assets)]), (test_res_phase, [])):
    w(f'\t\t{ph} /* Resources */ = {{')
    w('\t\t\tisa = PBXResourcesBuildPhase;')
    w('\t\t\tbuildActionMask = 2147483647;')
    w('\t\t\tfiles = (')
    for fid, fname in files: w(f'\t\t\t\t{fid} /* {fname} in Resources */,')
    w('\t\t\t);')
    w('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    w('\t\t};')
w('/* End PBXResourcesBuildPhase section */')
w('')
w('/* Begin PBXSourcesBuildPhase section */')
for ph, tname, files in ((app_src_phase,'I4A',app_sources),(test_src_phase,'I4ATests',test_sources)):
    w(f'\t\t{ph} /* Sources */ = {{')
    w('\t\t\tisa = PBXSourcesBuildPhase;')
    w('\t\t\tbuildActionMask = 2147483647;')
    w('\t\t\tfiles = (')
    for f in files: w(f'\t\t\t\t{bf(tname,f)} /* {f} in Sources */,')
    w('\t\t\t);')
    w('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    w('\t\t};')
w('/* End PBXSourcesBuildPhase section */')
w('')
w('/* Begin PBXTargetDependency section */')
w(f'\t\t{dep} /* PBXTargetDependency */ = {{')
w('\t\t\tisa = PBXTargetDependency;')
w(f'\t\t\ttarget = {app_target} /* I4A */;')
w(f'\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;')
w('\t\t};')
w('/* End PBXTargetDependency section */')
w('')

def q(v):
    v = str(v)
    import re
    if re.fullmatch(r'[A-Za-z0-9_./$]+', v) and v != '': return v
    return '"' + v.replace('\\','\\\\').replace('"','\\"') + '"'

common_proj = {
 'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ANALYZER_NONNULL':'YES','CLANG_CXX_LANGUAGE_STANDARD':'gnu++20','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','CLANG_ENABLE_OBJC_WEAK':'YES',
 'CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING':'YES','CLANG_WARN_BOOL_CONVERSION':'YES','CLANG_WARN_COMMA':'YES','CLANG_WARN_CONSTANT_CONVERSION':'YES','CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS':'YES',
 'CLANG_WARN_DIRECT_OBJC_ISA_USAGE':'YES_ERROR','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','CLANG_WARN_EMPTY_BODY':'YES','CLANG_WARN_ENUM_CONVERSION':'YES','CLANG_WARN_INFINITE_RECURSION':'YES',
 'CLANG_WARN_INT_CONVERSION':'YES','CLANG_WARN_NON_LITERAL_NULL_CONVERSION':'YES','CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF':'YES','CLANG_WARN_OBJC_LITERAL_CONVERSION':'YES','CLANG_WARN_OBJC_ROOT_CLASS':'YES_ERROR',
 'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER':'YES','CLANG_WARN_RANGE_LOOP_ANALYSIS':'YES','CLANG_WARN_STRICT_PROTOTYPES':'YES','CLANG_WARN_SUSPICIOUS_MOVE':'YES','CLANG_WARN_UNGUARDED_AVAILABILITY':'YES_AGGRESSIVE',
 'CLANG_WARN_UNREACHABLE_CODE':'YES','CLANG_WARN__DUPLICATE_METHOD_MATCH':'YES','COPY_PHASE_STRIP':'NO','ENABLE_STRICT_OBJC_MSGSEND':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','GCC_NO_COMMON_BLOCKS':'YES',
 'GCC_WARN_64_TO_32_BIT_CONVERSION':'YES','GCC_WARN_ABOUT_RETURN_TYPE':'YES_ERROR','GCC_WARN_UNDECLARED_SELECTOR':'YES','GCC_WARN_UNINITIALIZED_AUTOS':'YES_AGGRESSIVE','GCC_WARN_UNUSED_FUNCTION':'YES',
 'GCC_WARN_UNUSED_VARIABLE':'YES','IPHONEOS_DEPLOYMENT_TARGET':'16.0','MTL_FAST_MATH':'YES','SDKROOT':'iphoneos',
}
proj_debug_s = dict(common_proj, **{'DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','GCC_DYNAMIC_NO_PIC':'NO','GCC_OPTIMIZATION_LEVEL':'0',
 'GCC_PREPROCESSOR_DEFINITIONS':['DEBUG=1','$(inherited)'],'MTL_ENABLE_DEBUG_INFO':'INCLUDE_SOURCE','ONLY_ACTIVE_ARCH':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)','SWIFT_OPTIMIZATION_LEVEL':'-Onone'})
proj_release_s = dict(common_proj, **{'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','ENABLE_NS_ASSERTIONS':'NO','MTL_ENABLE_DEBUG_INFO':'NO','SWIFT_COMPILATION_MODE':'wholemodule','VALIDATE_PRODUCT':'YES'})
app_s = {
 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1',
 'ENABLE_PREVIEWS':'YES','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_FILE':'I4A/Info.plist',
 'INFOPLIST_KEY_CFBundleDisplayName':'I4A',
 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption':'NO',
 'INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.productivity',
 'INFOPLIST_KEY_NSCameraUsageDescription':'게시물과 스토리를 촬영해 올리려면 카메라 접근이 필요해요.',
 'INFOPLIST_KEY_NSMicrophoneUsageDescription':'동영상을 촬영해 올리려면 마이크 접근이 필요해요.',
 'INFOPLIST_KEY_NSPhotoLibraryUsageDescription':'사진과 동영상을 골라 올리려면 사진 보관함 접근이 필요해요.',
 'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription':'사진과 동영상을 사진 보관함에 저장하려면 접근이 필요해요.',
 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES',
 'INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait',
 'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'MARKETING_VERSION':'1.0','PRODUCT_BUNDLE_IDENTIFIER':'$(I4A_BUNDLE_ID)','PRODUCT_NAME':'$(TARGET_NAME)',
 'SWIFT_EMIT_LOC_STRINGS':'YES','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'1',
}
test_s = {
 'BUNDLE_LOADER':'$(TEST_HOST)','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','GENERATE_INFOPLIST_FILE':'YES','IPHONEOS_DEPLOYMENT_TARGET':'16.0',
 'MARKETING_VERSION':'1.0','PRODUCT_BUNDLE_IDENTIFIER':'$(I4A_BUNDLE_ID).tests','PRODUCT_NAME':'$(TARGET_NAME)','SWIFT_EMIT_LOC_STRINGS':'NO','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'1',
 'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/I4A.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/I4A',
}
def cfg(cid, name, settings, base=None):
    w(f'\t\t{cid} /* {name} */ = {{')
    w('\t\t\tisa = XCBuildConfiguration;')
    if base: w(f'\t\t\tbaseConfigurationReference = {base} /* Base.xcconfig */;')
    w('\t\t\tbuildSettings = {')
    for k in sorted(settings):
        v = settings[k]
        if isinstance(v, list):
            w(f'\t\t\t\t{k} = (')
            for x in v: w(f'\t\t\t\t\t{q(x)},')
            w('\t\t\t\t);')
        else:
            w(f'\t\t\t\t{k} = {q(v)};')
    w('\t\t\t};')
    w(f'\t\t\tname = {name};')
    w('\t\t};')
w('/* Begin XCBuildConfiguration section */')
cfg(proj_debug,'Debug',proj_debug_s); cfg(proj_release,'Release',proj_release_s)
base = ref(base_xcconfig)
cfg(app_debug,'Debug',app_s,base); cfg(app_release,'Release',app_s,base)
cfg(test_debug,'Debug',test_s,base); cfg(test_release,'Release',test_s,base)
w('/* End XCBuildConfiguration section */')
w('')
w('/* Begin XCConfigurationList section */')
for lid, kind, name, d, r in ((proj_cfg_list,'PBXProject','I4A',proj_debug,proj_release),(app_cfg_list,'PBXNativeTarget','I4A',app_debug,app_release),(test_cfg_list,'PBXNativeTarget','I4ATests',test_debug,test_release)):
    w(f'\t\t{lid} /* Build configuration list for {kind} "{name}" */ = {{')
    w('\t\t\tisa = XCConfigurationList;')
    w('\t\t\tbuildConfigurations = (')
    w(f'\t\t\t\t{d} /* Debug */,')
    w(f'\t\t\t\t{r} /* Release */,')
    w('\t\t\t);')
    w('\t\t\tdefaultConfigurationIsVisible = 0;')
    w('\t\t\tdefaultConfigurationName = Release;')
    w('\t\t};')
w('/* End XCConfigurationList section */')
w('\t};')
w(f'\trootObject = {proj} /* Project object */;')
w('}')

pdir = os.path.join(root,'I4A.xcodeproj')
os.makedirs(os.path.join(pdir,'xcshareddata','xcschemes'), exist_ok=True)
open(os.path.join(pdir,'project.pbxproj'),'w').write('\n'.join(out)+'\n')

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "I4A.app"
               BlueprintName = "I4A"
               ReferencedContainer = "container:I4A.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "I4ATests.xctest"
               BlueprintName = "I4ATests"
               ReferencedContainer = "container:I4A.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "I4A.app"
            BlueprintName = "I4A"
            ReferencedContainer = "container:I4A.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "I4A.app"
            BlueprintName = "I4A"
            ReferencedContainer = "container:I4A.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
open(os.path.join(pdir,'xcshareddata','xcschemes','I4A.xcscheme'),'w').write(scheme)
print('ok', len(app_sources), len(test_sources))
