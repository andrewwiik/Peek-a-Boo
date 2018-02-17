#import "../headers/Preferences/PSListController.h"

@interface PABRootListController : PSListController
-(NSDictionary*)trimDataSource:(NSDictionary*)dataSource;
-(NSMutableArray*)appSpecifiers;
@end
