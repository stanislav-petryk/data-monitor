#include <Cocoa/Cocoa.h>
#include <chrono>
#include <cstdio>
#include <mach/mach.h>
#include <sstream>
#include <string>
#include <thread>

// get mac data

std::string execCommand(const char *cmd) {
  char buffer[128];
  std::string result = "";
  FILE *pipe = popen(cmd, "r");
  if (!pipe)
    return "Error";
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    result += buffer;
  }
  pclose(pipe);
  result.erase(result.find_last_not_of("\n") + 1);
  return result;
}

std::string getBatteryPercent() {
  return execCommand("pmset -g batt | grep -Eo '\\d+%' | head -1");
}

std::string getBatteryMaxCapacity() {
  return execCommand(
             "system_profiler SPPowerDataType | grep 'Maximum Capacity'")
      .substr(28);
}

std::string getBatteryTemp() {
  std::string temp = execCommand(
      "ioreg -rn AppleSmartBattery | grep -i Temperature | awk '{print $3}'");
  temp = temp.erase(temp.find_last_not_of(' ') + 1);
  temp = temp.substr(temp.size() - 4);
  temp = std::to_string(stod(temp) / 100).substr(0, 4);
  return temp;
}

std::string getGPUUsage() {
  std::string cpuUsage = execCommand("sudo /usr/local/bin/gpu_idle");
  cpuUsage = std::to_string(std::ceil(100 - stod(cpuUsage.substr(0, 5))));
  int dotPosition = cpuUsage.find('.');

  return cpuUsage.substr(0, dotPosition) + "%";
}

int getCPUUsage() {
  natural_t cpuCount;
  processor_info_array_t infoArray;
  mach_msg_type_number_t infoCount;
  static processor_info_array_t prevInfoArray = NULL;
  static mach_msg_type_number_t prevInfoCount = 0;
  static natural_t prevCPUCount = 0;

  kern_return_t kr =
      host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount,
                          &infoArray, &infoCount);
  if (kr != KERN_SUCCESS)
    return -1;

  float totalUsage = 0;
  for (unsigned i = 0; i < cpuCount; i++) {
    float user, system, idle, nice;
    if (prevInfoArray) {
      unsigned int index = CPU_STATE_MAX * i;
      user = infoArray[index + CPU_STATE_USER] -
             prevInfoArray[index + CPU_STATE_USER];
      system = infoArray[index + CPU_STATE_SYSTEM] -
               prevInfoArray[index + CPU_STATE_SYSTEM];
      idle = infoArray[index + CPU_STATE_IDLE] -
             prevInfoArray[index + CPU_STATE_IDLE];
      nice = infoArray[index + CPU_STATE_NICE] -
             prevInfoArray[index + CPU_STATE_NICE];
    }
    else {
      unsigned int index = CPU_STATE_MAX * i;
      user = infoArray[index + CPU_STATE_USER];
      system = infoArray[index + CPU_STATE_SYSTEM];
      idle = infoArray[index + CPU_STATE_IDLE];
      nice = infoArray[index + CPU_STATE_NICE];
    }

    float total = user + system + idle + nice;
    totalUsage += (user + system + nice) / total * 100.0f;
  }

  if (prevInfoArray)
    vm_deallocate(mach_task_self(), (vm_address_t)prevInfoArray,
                  sizeof(integer_t) * prevInfoCount);

  prevInfoArray = infoArray;
  prevInfoCount = infoCount;
  prevCPUCount = cpuCount;

  return (int)(totalUsage / cpuCount);
}

// vars

CGFloat offsetFromTop = 25;
CGFloat offsetFromLeft = 2;
NSWindow *gOverlayWindow = nil;

BOOL batteryEnabled = true;
BOOL maxCapEnabled = true;
BOOL tempEnabled = true;
BOOL cpuLoadEnabled = true;
BOOL gpuLoadEnabled = true;

// save data

void savePreferences() {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:(int)offsetFromLeft forKey:@"offsetFromLeft"];
  [defaults setInteger:(int)offsetFromTop forKey:@"offsetFromTop"];
  [defaults setBool:(BOOL)batteryEnabled forKey:@"batteryEnabled"];
  [defaults setBool:(BOOL)maxCapEnabled forKey:@"maxCapEnabled"];
  [defaults setBool:(BOOL)tempEnabled forKey:@"tempEnabled"];
  [defaults setBool:(BOOL)cpuLoadEnabled forKey:@"cpuLoadEnabled"];
  [defaults setBool:(BOOL)gpuLoadEnabled forKey:@"gpuLoadEnabled"];
  [defaults synchronize];
}

void loadPreferences() {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  if ([defaults objectForKey:@"offsetFromLeft"])
    offsetFromLeft = (CGFloat)[defaults integerForKey:@"offsetFromLeft"];

  if ([defaults objectForKey:@"offsetFromTop"])
    offsetFromTop = (CGFloat)[defaults integerForKey:@"offsetFromTop"];

  if ([defaults objectForKey:@"batteryEnabled"])
    batteryEnabled = (BOOL)[defaults boolForKey:@"batteryEnabled"];

  if ([defaults objectForKey:@"maxCapEnabled"])
    maxCapEnabled = (BOOL)[defaults boolForKey:@"maxCapEnabled"];

  if ([defaults objectForKey:@"tempEnabled"])
    tempEnabled = (BOOL)[defaults boolForKey:@"tempEnabled"];

  if ([defaults objectForKey:@"cpuLoadEnabled"])
    cpuLoadEnabled = (BOOL)[defaults boolForKey:@"cpuLoadEnabled"];

  if ([defaults objectForKey:@"gpuLoadEnabled"])
    gpuLoadEnabled = (BOOL)[defaults boolForKey:@"gpuLoadEnabled"];
}

// interface

static NSTextField *makeLabel(NSString *text) {
  NSTextField *label = [[NSTextField alloc] init];
  label.stringValue = text;
  label.bezeled = NO;
  label.drawsBackground = NO;
  label.editable = NO;
  label.selectable = NO;
  label.font = [NSFont systemFontOfSize:14];
  label.alignment = NSTextAlignmentRight;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  return label;
}

static NSButton *makeButton(NSString *title, SEL action, id target) {
  NSButton *button = [[NSButton alloc] init];
  button.title = title;
  button.bezelStyle = NSBezelStyleRounded;
  button.target = target;
  button.action = action;
  button.translatesAutoresizingMaskIntoConstraints = NO;
  return button;
}

static NSButton *makeSwitch(NSString *title, id target, SEL action,
                            BOOL state) {
  NSButton *sw = [[NSButton alloc] init];
  sw.title = title;
  sw.buttonType = NSButtonTypeSwitch;
  sw.state = state;
  sw.target = target;
  sw.action = action;
  sw.translatesAutoresizingMaskIntoConstraints = NO;
  return sw;
}

static NSTextField *makeTextField(NSString *initialValue, id target, SEL action,
                                  NSInteger tag) {
  NSTextField *field = [[NSTextField alloc] init];
  field.stringValue = initialValue;
  field.tag = tag;
  field.target = target;
  field.action = action;
  field.translatesAutoresizingMaskIntoConstraints = NO;
  return field;
}

void updateOverlayPosition() {
  if (!gOverlayWindow)
    return;

  NSScreen *screen = [NSScreen mainScreen];
  NSRect screenFrame = [screen frame];

  CGFloat windowWidth = gOverlayWindow.frame.size.width;
  CGFloat windowHeight = gOverlayWindow.frame.size.height;

  NSRect newFrame = NSMakeRect(
      offsetFromLeft, NSMaxY(screenFrame) - windowHeight - offsetFromTop,
      windowWidth, windowHeight);

  dispatch_async(dispatch_get_main_queue(), ^{
    [gOverlayWindow setFrame:newFrame display:YES animate:NO];
    [gOverlayWindow displayIfNeeded];
  });
}

@interface BackgroundView : NSView
@end

@implementation BackgroundView

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)mouseDown:(NSEvent *)event {
  [self.window makeFirstResponder:self];
}

@end

@interface PreferencesWindowController : NSWindowController
@end

@implementation PreferencesWindowController

- (instancetype)init {
  NSRect frame = NSMakeRect(0, 0, 350, 350);

  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                  backing:NSBackingStoreBuffered
                    defer:NO];

  window.title = @"Preferences";
  window.releasedWhenClosed = NO;
  window.titlebarAppearsTransparent = YES;

  self = [super initWithWindow:window];
  if (self) {
    [self setupUI];
  }
  return self;
}

- (void)setupUI {
  BackgroundView *content =
      [[BackgroundView alloc] initWithFrame:self.window.contentView.bounds];
  self.window.contentView = content;

  NSTextField *title = makeLabel(@"Overlay Position:");
  [content addSubview:title];
  [NSLayoutConstraint activateConstraints:@[
    [title.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
    [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:20]
  ]];

  NSTextField *xLabel = makeLabel(@"Left:");
  [content addSubview:xLabel];

  NSTextField *xField =
      makeTextField([NSString stringWithFormat:@"%d", (int)offsetFromLeft],
                    self, @selector(resetPosition:), 1);
  [content addSubview:xField];

  [NSLayoutConstraint activateConstraints:@[
    [xLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
    [xField.topAnchor constraintEqualToAnchor:xLabel.topAnchor],
    [xLabel.trailingAnchor constraintEqualToAnchor:content.centerXAnchor
                                          constant:-5],
    [xField.leadingAnchor constraintEqualToAnchor:content.centerXAnchor
                                         constant:5],
    [xField.widthAnchor constraintEqualToConstant:80]
  ]];

  NSTextField *yLabel = makeLabel(@"Top:");
  [content addSubview:yLabel];

  NSTextField *yField =
      makeTextField([NSString stringWithFormat:@"%d", (int)offsetFromTop], self,
                    @selector(resetPosition:), 2);
  [content addSubview:yField];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(textFieldChanged:)
             name:NSControlTextDidChangeNotification
           object:xField];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(textFieldChanged:)
             name:NSControlTextDidChangeNotification
           object:yField];

  [NSLayoutConstraint activateConstraints:@[
    [yLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:40],
    [yField.topAnchor constraintEqualToAnchor:yLabel.topAnchor],
    [yLabel.trailingAnchor constraintEqualToAnchor:content.centerXAnchor
                                          constant:-5],
    [yField.leadingAnchor constraintEqualToAnchor:content.centerXAnchor
                                         constant:5],
    [yField.widthAnchor constraintEqualToConstant:80]
  ]];

  NSButton *resetButton = makeButton(@"Reset", @selector(resetPosition:), self);
  [content addSubview:resetButton];

  [NSLayoutConstraint activateConstraints:@[
    [resetButton.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                          constant:70],
    [resetButton.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
  ]];

  NSTextField *dataTitle = makeLabel(@"Data that will display:");
  [content addSubview:dataTitle];

  [NSLayoutConstraint activateConstraints:@[
    [dataTitle.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                        constant:120],
    [dataTitle.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
  ]];

  NSButton *batteryCheckbox =
      makeSwitch(@"Battery charge", self, @selector(batteryCheckboxToggled:),
                 batteryEnabled);
  [content addSubview:batteryCheckbox];

  [NSLayoutConstraint activateConstraints:@[
    [batteryCheckbox.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                              constant:150],
    [batteryCheckbox.centerXAnchor
        constraintEqualToAnchor:content.centerXAnchor],
  ]];

  NSButton *maxCapCheckbox =
      makeSwitch(@"Max battery capacity", self,
                 @selector(maxCapCheckboxToggled:), maxCapEnabled);
  [content addSubview:maxCapCheckbox];

  [NSLayoutConstraint activateConstraints:@[
    [maxCapCheckbox.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                             constant:180],
    [maxCapCheckbox.centerXAnchor
        constraintEqualToAnchor:content.centerXAnchor],
  ]];

  NSButton *tempCheckbox =
      makeSwitch(@"Battery temperature", self, @selector(tempCheckboxToggled:),
                 tempEnabled);
  [content addSubview:tempCheckbox];

  [NSLayoutConstraint activateConstraints:@[
    [tempCheckbox.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                           constant:210],
    [tempCheckbox.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
  ]];

  NSButton *cpuLoadCheckbox = makeSwitch(
      @"CPU Load", self, @selector(cpuLoadCheckboxToggled:), cpuLoadEnabled);
  [content addSubview:cpuLoadCheckbox];

  [NSLayoutConstraint activateConstraints:@[
    [cpuLoadCheckbox.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                              constant:240],
    [cpuLoadCheckbox.centerXAnchor
        constraintEqualToAnchor:content.centerXAnchor],
  ]];

  NSButton *gpuLoadCheckbox = makeSwitch(
      @"GPU Load", self, @selector(gpuLoadCheckboxToggled:), gpuLoadEnabled);
  [content addSubview:gpuLoadCheckbox];

  [NSLayoutConstraint activateConstraints:@[
    [gpuLoadCheckbox.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                              constant:270],
    [gpuLoadCheckbox.centerXAnchor
        constraintEqualToAnchor:content.centerXAnchor],
  ]];
}

- (void)resetPosition:(id)sender {
  NSTextField *xField = [self.window.contentView viewWithTag:1];
  NSTextField *yField = [self.window.contentView viewWithTag:2];

  [xField setStringValue:@"2"];
  [yField setStringValue:@"25"];

  [self updateCoords:xField];
  [self updateCoords:yField];
}

- (void)textFieldChanged:(NSNotification *)note {
  NSTextField *field = note.object;

  if (field.tag == 1) {
    offsetFromLeft = field.intValue;
  }
  else if (field.tag == 2) {
    offsetFromTop = field.intValue;
  }

  updateOverlayPosition();
  savePreferences();
}

- (void)updateCoords:(NSTextField *)sender {
  if (sender.tag == 1) {
    offsetFromLeft = sender.intValue;
  }
  else if (sender.tag == 2) {
    offsetFromTop = sender.intValue;
  }

  updateOverlayPosition();
  savePreferences();
}

- (void)batteryCheckboxToggled:(NSButton *)sender {
  batteryEnabled = (sender.state == NSControlStateValueOn);
  savePreferences();
}

- (void)maxCapCheckboxToggled:(NSButton *)sender {
  maxCapEnabled = (sender.state == NSControlStateValueOn);
  savePreferences();
}

- (void)tempCheckboxToggled:(NSButton *)sender {
  tempEnabled = (sender.state == NSControlStateValueOn);
  savePreferences();
}

- (void)cpuLoadCheckboxToggled:(NSButton *)sender {
  cpuLoadEnabled = (sender.state == NSControlStateValueOn);
  savePreferences();
}

- (void)gpuLoadCheckboxToggled:(NSButton *)sender {
  gpuLoadEnabled = (sender.state == NSControlStateValueOn);
  savePreferences();
}

- (void)keyDown:(NSEvent *)event {
  unsigned short code = [event keyCode];
  if ((event.modifierFlags & NSEventModifierFlagCommand)) {
    if (code == 13) {
      [self.window performClose:nil];
      return;
    }
    else if (code == 12) {
      [NSApp terminate:nil];
      return;
    }
  }

  [super keyDown:event];
}

@end

@interface StatusApp : NSObject
@property(strong) NSStatusItem *statusItem;
@property(strong) PreferencesWindowController *prefsWC;
- (void)setupStatusItem;
@end

@implementation StatusApp

- (void)setupStatusItem {
  self.statusItem = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];

  NSImage *icon = [[NSImage alloc]
      initWithContentsOfFile:[[NSBundle mainBundle]
                                 pathForResource:@"DataMonitorIcon"
                                          ofType:@"png"]];
  [icon setSize:NSMakeSize(23, 23)];
  self.statusItem.button.image = icon;

  NSMenu *menu = [[NSMenu alloc] init];
  NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                    action:@selector(quitApp:)
                                             keyEquivalent:@""];

  quitItem.keyEquivalent = @"q";
  quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;

  NSMenuItem *preferences =
      [[NSMenuItem alloc] initWithTitle:@"Preferences"
                                 action:@selector(preferences:)
                          keyEquivalent:@","];
  preferences.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  preferences.target = self;
  [menu addItem:preferences];

  [menu addItem:[NSMenuItem separatorItem]];

  quitItem.target = self;
  [menu addItem:quitItem];

  self.statusItem.menu = menu;
}

- (void)setupMenu {
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
  NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:appMenuItem];
  [NSApp setMainMenu:mainMenu];

  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
  NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                    action:@selector(quitApp:)
                                             keyEquivalent:@"q"];
  quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  quitItem.target = self;
  [appMenu addItem:quitItem];

  [appMenuItem setSubmenu:appMenu];
}

- (void)quitApp:(id)sender {
  [NSApp terminate:nil];
}

- (void)preferences:(id)sender {
  if (!self.prefsWC) {
    self.prefsWC = [[PreferencesWindowController alloc] init];
  }

  [self.prefsWC showWindow:nil];
  [self.prefsWC.window center];
  [NSApp activateIgnoringOtherApps:YES];
}

@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];

    loadPreferences();

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSRect screenF = [[NSScreen mainScreen] frame];
    CGFloat windowWidth = 100;
    CGFloat windowHeight = 120;

    NSRect frame = NSMakeRect(NSMaxX(screenF) - windowWidth - offsetFromLeft,
                              NSMaxY(screenF) - windowHeight - offsetFromTop,
                              windowWidth, windowHeight);

    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:frame
                                    styleMask:NSWindowStyleMaskBorderless
                                      backing:NSBackingStoreBuffered
                                        defer:NO];

    gOverlayWindow = window;
    updateOverlayPosition();

    [window setLevel:NSStatusWindowLevel];
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor colorWithWhite:0 alpha:0.0]];
    [window setReleasedWhenClosed:NO];
    [window setIgnoresMouseEvents:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];

    NSTextField *label =
        [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 120)];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setTextColor:[NSColor whiteColor]];
    [label setFont:[NSFont systemFontOfSize:12]];
    [window.contentView addSubview:label];

    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = [screen frame];
    NSPoint newOrigin = NSMakePoint(NSMinX(frame), offsetFromTop);
    [window setFrameOrigin:newOrigin];

    [window makeKeyAndOrderFront:nil];

    StatusApp *manager = [[StatusApp alloc] init];
    [manager setupMenu];
    [manager setupStatusItem];

    std::thread([label]() {
      int i = 0;
      __block std::string gpuUsage;
      std::string battery = getBatteryPercent();
      std::string maxCap = getBatteryMaxCapacity();
      std::string temp = getBatteryTemp();

      while (true) {
        std::stringstream ss;
        if (i == 3) {
          battery = getBatteryPercent();
          maxCap = getBatteryMaxCapacity();
          temp = getBatteryTemp();
          i = 0;
          dispatch_async(
              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                gpuUsage = getGPUUsage();
              });
        }
        i++;
        if (batteryEnabled)
          ss << "Battery: " << battery << std::endl;
        if (maxCapEnabled)
          ss << "MaxCap: " << maxCap << std::endl;
        if (tempEnabled)
          ss << "Temp: " << temp << "°C\n";
        if (cpuLoadEnabled)
          ss << "CPU Load: " << getCPUUsage() << "%" << std::endl;
        if (gpuLoadEnabled)
          ss << "GPU Load: " << gpuUsage;

        NSString *nsStr = [NSString stringWithUTF8String:ss.str().c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
          [label setStringValue:nsStr];
        });
        std::this_thread::sleep_for(std::chrono::seconds(1));
      }
    }).detach();

    [app run];
  }
  return 0;
}
