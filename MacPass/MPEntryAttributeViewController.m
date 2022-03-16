//
//  MPEntryAttributeViewController.m
//  MacPass
//
//  Created by Michael Starke on 14.10.21.
//  Copyright © 2021 HicknHack Software GmbH. All rights reserved.
//

#import "MPEntryAttributeViewController.h"
#import <HNHUi/HNHUi.h>
#import <KeePassKit/KeePassKit.h>
#import "MPPasteBoardController.h"
#import "MPInspectorEditorView.h"

NSString *nameForDefaultKey(NSString *key) {
  static NSDictionary *mapping;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    mapping = @{ kKPKTitleKey: NSLocalizedString(@"TITTLE_ATTRIBUTE_KEY", @"Localized name for title attribute"),
                 kKPKUsernameKey: NSLocalizedString(@"USERNAME_ATTRIBUTE_KEY", @"Localized name for username attribute"),
                 kKPKPasswordKey: NSLocalizedString(@"PASSWORD_ATTRIBUTE_KEY", @"Localized name for password attribute"),
                 kKPKURLKey: NSLocalizedString(@"URL_ATTRIBUTE_KEY", @"Localized name for URL attribute") };
  });
  return mapping[key];
}


@interface MPEntryAttributeViewController ()

@property (nonatomic, readonly, getter=isDefaultAttributeEditor) BOOL defaultAttributeEditor;
@property (nonatomic, readonly, getter=isPasswordAttributeEditor) BOOL passwordAttributeEditor;

@end

@implementation MPEntryAttributeViewController

@synthesize isEditor = _isEditor;

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if(self) {
    _isEditor = NO;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if(self) {
    _isEditor = NO;
    NSString *selectorString = [coder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(attributeSelector))];
    if(selectorString) {
      self.attributeSelector = NSSelectorFromString(selectorString);
    }
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  // editor state will be set to NO after decoding
  [coder encodeObject:NSStringFromSelector(self.attributeSelector) forKey:NSStringFromSelector(@selector(attributeSelector))];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didEnterMouse:) name:MPInspectorEditorViewMouseEnteredNotification object:self.view];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didExitMouse:) name:MPInspectorEditorViewMouseExitedNotification object:self.view];
  
  self.toggleProtectedButton.action = @selector(toggleDisplay:);
  self.toggleProtectedButton.target = self.valueTextField;
  
  self.actionButton.action = @selector(_copyText:);
  self.actionButton.target = self;
  self.actionButton.hidden = YES;
  self.actionButton.title = NSLocalizedString(@"COPY", "Button title for copying an attribute value");
  
  NSDictionary *bindingOptions = @{ NSNullPlaceholderBindingOption :  NSLocalizedString(@"NONE", "Placeholder text for input fields if no entry or group is selected"),
                                    NSConditionallySetsHiddenBindingOption : @(NO),
                                    NSConditionallySetsEnabledBindingOption : @(NO),
                                    NSConditionallySetsEditableBindingOption : @(NO) };
  
  
  NSString *valueKeyPath = [NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(value))];
  if(self.isDefaultAttributeEditor) {
    valueKeyPath = [NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)),NSStringFromSelector(@selector(entry)), NSStringFromSelector(self.attributeSelector)];
  }
  [self.valueTextField bind:NSValueBinding
                   toObject:self
                withKeyPath:valueKeyPath
                    options:bindingOptions];
  
  if(!self.isDefaultAttributeEditor) {
    NSString *keyKeyPath = [NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(key))];
    [self.keyTextField bind:NSValueBinding
                   toObject:self
                withKeyPath:keyKeyPath
                    options:bindingOptions];
  }
  if(self.isPasswordAttributeEditor) {
    self.toggleProtectedButton.image = [NSImage imageNamed:NSImageNameQuickLookTemplate];
    NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:13.0];
    self.valueTextField.font = font;
    // TODO: setup pretty password value transformer
  }
  [self updateValuesAndEditing];
}

- (KPKAttribute *)representedAttribute {
  if([self.representedObject isKindOfClass:KPKAttribute.class]) {
    return (KPKAttribute *)self.representedObject;
  }
  return nil;
}

- (BOOL)isDefaultAttributeEditor {
  return (self.attributeSelector != NULL);
}

- (BOOL)isPasswordAttributeEditor {
  return self.attributeSelector == @selector(password);
}

- (void)setIsEditor:(BOOL)isEditor {
  _isEditor = isEditor;
  [self updateValuesAndEditing];
}

- (void)setRepresentedObject:(id)representedObject {
  if(self.representedAttribute) {
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:KPKDidChangeAttributeNotification
                                                object:self.representedObject];
  }
  super.representedObject = representedObject;
  if(self.representedAttribute) {
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:(@selector(_didChangeAttribute:))
                                               name:KPKDidChangeAttributeNotification
                                             object:self.representedAttribute];
    
  }  
  // bind with read-only setup and value transformer for names?
  if(self.isDefaultAttributeEditor) {
    [self.keyTextField unbind:NSValueBinding];
    NSString *localizedKey = nameForDefaultKey(self.representedAttribute.key);
    if(localizedKey) {
      self.keyTextField.stringValue = localizedKey;
    }
    else {
      self.keyTextField.stringValue = self.representedAttribute.key ? self.representedAttribute.key : @"";
    }
  }
  
  [self updateValuesAndEditing];
}

- (void)_copyText:(id)sender {
  [self performCopyForText:self.valueTextField.stringValue];
}

- (BOOL)textField:(NSTextField *)textField textView:(NSTextView *)textView performAction:(SEL)action {
  if(action != @selector(copy:)) {
    return YES;
  }
  
  // Only copy action
  
  NSMutableString *selectedValue = [[NSMutableString alloc] init];
  for(NSValue *rangeValue in textView.selectedRanges) {
    [selectedValue appendString:[textView.string substringWithRange:rangeValue.rangeValue]];
  }
  if(selectedValue.length == 0) {
    [selectedValue setString:textField.stringValue];
  }
  [self performCopyForText:selectedValue];
  return NO;
}

- (void)performCopyForText:(NSString *)text {
  
  MPPasteboardOverlayInfoType info = MPPasteboardOverlayInfoCustom;
  NSString *name = @"";
  
  if([self.representedAttribute.key isEqual:kKPKUsernameKey]) {
    info = MPPasteboardOverlayInfoUsername;
  }
  else if([self.representedAttribute.key isEqual:kKPKPasswordKey]) {
    info = MPPasteboardOverlayInfoPassword;
  }
  else if([self.representedAttribute.key isEqual:kKPKURLKey]) {
    info = MPPasteboardOverlayInfoURL;
  }
  else if([self.representedAttribute.key isEqual:kKPKTitleKey]) {
    name = NSLocalizedString(@"TITLE", "Displayed name when title field was copied");
  }
  else {
    name = self.representedAttribute.key;
  }
  [MPPasteBoardController.defaultController copyObject:text overlayInfo:info name:name atView:self.view];
}

- (void)_didChangeAttribute:(NSNotification *)notification {
  [self updateValuesAndEditing];
}

- (void)updateValuesAndEditing {
  // values
  self.view.hidden = self.isEditor ? NO : self.representedAttribute.value.length == 0;
    
  self.valueTextField.showPassword = !self.representedAttribute.protect;
  
  // editor
  self.keyTextField.editable = !self.isDefaultAttributeEditor && self.isEditor;
  self.valueTextField.editable = self.isEditor;
  self.keyTextField.selectable = YES;
  self.valueTextField.selectable = YES;
  self.toggleProtectedButton.hidden = self.isDefaultAttributeEditor ? !self.isPasswordAttributeEditor : NO;
  self.generatePasswordButton.hidden = self.isEditor ? !self.isPasswordAttributeEditor : YES;
  
  self.removeButton.hidden = !self.isEditor ? YES : self.isDefaultAttributeEditor;
  
  // set draws background first, since bezeld might have side effects
  self.valueTextField.drawsBackground = self.isEditor;
  self.valueTextField.bordered = self.isEditor;
  self.valueTextField.bezeled = self.isEditor;
}

- (void)_didEnterMouse:(NSNotification *)notification {
  self.actionButton.hidden = self.isEditor;
}

- (void)_didExitMouse:(NSNotification *)notification {
  self.actionButton.hidden = YES;
}

- (void)commitChanges {
  // to nothing
}

- (void)objectDidBeginEditing:(id<NSEditor>)editor {
  [self.view.window.windowController.document objectDidBeginEditing:editor];
  [super objectDidBeginEditing:editor];
}

- (void)objectDidEndEditing:(id<NSEditor>)editor {
  [self.view.window.windowController.document objectDidEndEditing:editor];
  [super objectDidEndEditing:editor];
}

- (void)commitEditingWithDelegate:(nullable id)delegate didCommitSelector:(nullable SEL)didCommitSelector contextInfo:(nullable void *)contextInfo {
  [super commitEditingWithDelegate:delegate didCommitSelector:didCommitSelector contextInfo:contextInfo];
}

@end

