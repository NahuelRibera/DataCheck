import { Application } from "@hotwired/stimulus";

import TabsController from "./tabs_controller";
import IssueFilterController from "./issue_filter_controller";
import ExpandableController from "./expandable_controller";
import ExecuteConfirmController from "./execute_confirm_controller";

const application = Application.start();
application.debug = false;
(window as any).Stimulus = application;

application.register("tabs", TabsController);
application.register("issue-filter", IssueFilterController);
application.register("expandable", ExpandableController);
application.register("execute-confirm", ExecuteConfirmController);

export default application;
