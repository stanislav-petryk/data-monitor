#include <AppKit/AppKit.h>
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
  [defaults synchronize];
}

void loadPreferences() {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  if ([defaults objectForKey:@"offsetFromLeft"])
    offsetFromLeft = (CGFloat)[defaults integerForKey:@"offsetFromLeft"];

  if ([defaults objectForKey:@"offsetFromTop"])
    offsetFromTop = (CGFloat)[defaults integerForKey:@"offsetFromTop"];
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
  label.alignment = NSTextAlignmentCenter;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  return label;
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

  NSTextField *title = makeLabel(@"Overlay Position (from top-left corner)");
  [content addSubview:title];

  [NSLayoutConstraint activateConstraints:@[
    [title.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
    [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:20]
  ]];

  NSTextField *xLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 200, 80, 24)];
  [xLabel setStringValue:@"Left:"];
  [xLabel setBezeled:NO];
  [xLabel setEditable:NO];
  [xLabel setDrawsBackground:NO];
  [content addSubview:xLabel];

  NSTextField *xField =
      [[NSTextField alloc] initWithFrame:NSMakeRect(50, 205, 80, 24)];
  [xField
      setStringValue:[NSString stringWithFormat:@"%d", (int)offsetFromLeft]];
  xField.tag = 1;
  xField.target = self;
  [content addSubview:xField];

  NSTextField *yLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 170, 80, 24)];
  [yLabel setStringValue:@"Top:"];
  [yLabel setBezeled:NO];
  [yLabel setEditable:NO];
  [yLabel setDrawsBackground:NO];
  [content addSubview:yLabel];

  NSTextField *yField =
      [[NSTextField alloc] initWithFrame:NSMakeRect(50, 175, 80, 24)];
  [yField setStringValue:[NSString stringWithFormat:@"%d", (int)offsetFromTop]];
  yField.tag = 2;
  yField.target = self;
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

  NSButton *resetBtn =
      [[NSButton alloc] initWithFrame:NSMakeRect(15, 140, 115, 28)];
  resetBtn.bezelStyle = NSBezelStyleRounded;
  resetBtn.title = @"Reset";
  resetBtn.target = self;
  resetBtn.action = @selector(resetPosition:);
  [content addSubview:resetBtn];

  NSTextField *dataTitle =
      [[NSTextField alloc] initWithFrame:NSMakeRect(5, 100, 250, 24)];
  [dataTitle setStringValue:@"Data that will display"];
  [dataTitle setBezeled:NO];
  [dataTitle setEditable:NO];
  [dataTitle setDrawsBackground:NO];
  [content addSubview:dataTitle];

  NSTextField *batteryLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 80, 150, 24)];
  [batteryLabel setStringValue:@"Battery charge"];
  [batteryLabel setBezeled:NO];
  [batteryLabel setEditable:NO];
  [batteryLabel setDrawsBackground:NO];
  [content addSubview:batteryLabel];
  NSButton *batteryCheckbox =
      [[NSButton alloc] initWithFrame:NSMakeRect(200, 80, 20, 24)];
  [batteryCheckbox setButtonType:NSButtonTypeSwitch];
  [batteryCheckbox setState:NSControlStateValueOn];
  [batteryCheckbox setTarget:self];
  [batteryCheckbox setAction:@selector(batteryCheckboxToggled:)];
  [content addSubview:batteryCheckbox];

  NSTextField *maxCapLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 60, 150, 24)];
  [maxCapLabel setStringValue:@"Max battery capacity"];
  [maxCapLabel setBezeled:NO];
  [maxCapLabel setEditable:NO];
  [maxCapLabel setDrawsBackground:NO];
  [content addSubview:maxCapLabel];
  NSButton *maxCapCheckbox =
      [[NSButton alloc] initWithFrame:NSMakeRect(200, 60, 20, 24)];
  [maxCapCheckbox setButtonType:NSButtonTypeSwitch];
  [maxCapCheckbox setState:NSControlStateValueOn];
  [maxCapCheckbox setTarget:self];
  [maxCapCheckbox setAction:@selector(maxCapCheckboxToggled:)];
  [content addSubview:maxCapCheckbox];

  NSTextField *tempLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 40, 150, 24)];
  [tempLabel setStringValue:@"Battery temperature"];
  [tempLabel setBezeled:NO];
  [tempLabel setEditable:NO];
  [tempLabel setDrawsBackground:NO];
  [content addSubview:tempLabel];
  NSButton *tempCheckbox =
      [[NSButton alloc] initWithFrame:NSMakeRect(200, 40, 20, 24)];
  [tempCheckbox setButtonType:NSButtonTypeSwitch];
  [tempCheckbox setState:NSControlStateValueOn];
  [tempCheckbox setTarget:self];
  [tempCheckbox setAction:@selector(tempCheckboxToggled:)];
  [content addSubview:tempCheckbox];

  NSTextField *cpuLoadLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 20, 80, 24)];
  [cpuLoadLabel setStringValue:@"CPU Load"];
  [cpuLoadLabel setBezeled:NO];
  [cpuLoadLabel setEditable:NO];
  [cpuLoadLabel setDrawsBackground:NO];
  [content addSubview:cpuLoadLabel];
  NSButton *cpuLoadCheckbox =
      [[NSButton alloc] initWithFrame:NSMakeRect(100, 20, 20, 24)];
  [cpuLoadCheckbox setButtonType:NSButtonTypeSwitch];
  [cpuLoadCheckbox setState:NSControlStateValueOn];
  [cpuLoadCheckbox setTarget:self];
  [cpuLoadCheckbox setAction:@selector(cpuLoadCheckboxToggled:)];
  [content addSubview:cpuLoadCheckbox];

  NSTextField *gpuLoadLabel =
      [[NSTextField alloc] initWithFrame:NSMakeRect(15, 0, 80, 24)];
  [gpuLoadLabel setStringValue:@"GPU Load"];
  [gpuLoadLabel setBezeled:NO];
  [gpuLoadLabel setEditable:NO];
  [gpuLoadLabel setDrawsBackground:NO];
  [content addSubview:gpuLoadLabel];
  NSButton *gpuLoadCheckbox =
      [[NSButton alloc] initWithFrame:NSMakeRect(100, 0, 20, 24)];
  [gpuLoadCheckbox setButtonType:NSButtonTypeSwitch];
  [gpuLoadCheckbox setState:NSControlStateValueOn];
  [gpuLoadCheckbox setTarget:self];
  [gpuLoadCheckbox setAction:@selector(gpuLoadCheckboxToggled:)];
  [content addSubview:gpuLoadCheckbox];
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
}

- (void)maxCapCheckboxToggled:(NSButton *)sender {
  maxCapEnabled = (sender.state == NSControlStateValueOn);
}

- (void)tempCheckboxToggled:(NSButton *)sender {
  tempEnabled = (sender.state == NSControlStateValueOn);
}

- (void)cpuLoadCheckboxToggled:(NSButton *)sender {
  cpuLoadEnabled = (sender.state == NSControlStateValueOn);
}

- (void)gpuLoadCheckboxToggled:(NSButton *)sender {
  gpuLoadEnabled = (sender.state == NSControlStateValueOn);
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

  // NSMenuItem *textItem = [[NSMenuItem alloc] initWithTitle:@"Hello world"
  //                                                   action:nil
  //                                            keyEquivalent:@""];
  // [menu insertItem:textItem atIndex:0];

  NSMenuItem *preferences =
      [[NSMenuItem alloc] initWithTitle:@"Preferences"
                                 action:@selector(preferences:)
                          keyEquivalent:@","];
  preferences.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  preferences.target = self;
  [menu addItem:preferences];

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
