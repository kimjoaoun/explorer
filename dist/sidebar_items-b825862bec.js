sidebarNodes={"extras":[{"group":"","headers":[{"anchor":"modules","id":"Modules"}],"id":"api-reference","title":"API Reference"},{"group":"","headers":[{"anchor":"introduction","id":"Introduction"},{"anchor":"installation","id":"Installation"},{"anchor":"reading-and-writing-data","id":"Reading and writing data"},{"anchor":"working-with-series","id":"Working with Series"},{"anchor":"working-with-dataframes","id":"Working with DataFrames"}],"id":"exploring_explorer","title":"Ten Minutes to Explorer"},{"group":"","headers":[{"anchor":"unreleased","id":"[Unreleased]"},{"anchor":"v0-1-1-2022-04-27","id":"[v0.1.1] - 2022-04-27"},{"anchor":"v0-1-0-2022-04-26","id":"[v0.1.0] - 2022-04-26"}],"id":"changelog","title":"Changelog"}],"modules":[{"group":"","id":"Explorer","sections":[],"title":"Explorer"},{"group":"","id":"Explorer.DataFrame","nodeGroups":[{"key":"types","name":"Types","nodes":[{"anchor":"t:column/0","id":"column/0"},{"anchor":"t:column_name/0","id":"column_name/0"},{"anchor":"t:column_names/0","id":"column_names/0"},{"anchor":"t:column_pairs/1","id":"column_pairs/1"},{"anchor":"t:columns/0","id":"columns/0"},{"anchor":"t:data/0","id":"data/0"},{"anchor":"t:t/0","id":"t/0"}]},{"key":"functions-single-table","name":"Functions: Single-table","nodes":[{"anchor":"arrange/2","id":"arrange/2"},{"anchor":"distinct/2","id":"distinct/2"},{"anchor":"drop_nil/2","id":"drop_nil/2"},{"anchor":"dummies/2","id":"dummies/2"},{"anchor":"filter/2","id":"filter/2"},{"anchor":"group_by/2","id":"group_by/2"},{"anchor":"head/2","id":"head/2"},{"anchor":"mutate/2","id":"mutate/2"},{"anchor":"new/2","id":"new/2"},{"anchor":"pivot_longer/3","id":"pivot_longer/3"},{"anchor":"pivot_wider/4","id":"pivot_wider/4"},{"anchor":"pull/2","id":"pull/2"},{"anchor":"rename/2","id":"rename/2"},{"anchor":"rename_with/3","id":"rename_with/3"},{"anchor":"sample/3","id":"sample/3"},{"anchor":"select/3","id":"select/3"},{"anchor":"slice/3","id":"slice/3"},{"anchor":"summarise/2","id":"summarise/2"},{"anchor":"table/2","id":"table/2"},{"anchor":"tail/2","id":"tail/2"},{"anchor":"take/2","id":"take/2"},{"anchor":"to_columns/2","id":"to_columns/2"},{"anchor":"to_rows/2","id":"to_rows/2"},{"anchor":"to_series/2","id":"to_series/2"},{"anchor":"ungroup/2","id":"ungroup/2"}]},{"key":"functions-multi-table","name":"Functions: Multi-table","nodes":[{"anchor":"concat_rows/1","id":"concat_rows/1"},{"anchor":"concat_rows/2","id":"concat_rows/2"},{"anchor":"join/3","id":"join/3"}]},{"key":"functions-introspection","name":"Functions: Introspection","nodes":[{"anchor":"dtypes/1","id":"dtypes/1"},{"anchor":"groups/1","id":"groups/1"},{"anchor":"n_columns/1","id":"n_columns/1"},{"anchor":"n_rows/1","id":"n_rows/1"},{"anchor":"names/1","id":"names/1"},{"anchor":"shape/1","id":"shape/1"}]},{"key":"functions-io","name":"Functions: IO","nodes":[{"anchor":"dump_csv/2","id":"dump_csv/2"},{"anchor":"from_csv!/2","id":"from_csv!/2"},{"anchor":"from_csv/2","id":"from_csv/2"},{"anchor":"from_ipc!/2","id":"from_ipc!/2"},{"anchor":"from_ipc/2","id":"from_ipc/2"},{"anchor":"from_ndjson/2","id":"from_ndjson/2"},{"anchor":"from_parquet/2","id":"from_parquet/2"},{"anchor":"to_csv!/3","id":"to_csv!/3"},{"anchor":"to_csv/3","id":"to_csv/3"},{"anchor":"to_ipc/3","id":"to_ipc/3"},{"anchor":"to_ndjson/2","id":"to_ndjson/2"},{"anchor":"to_parquet/2","id":"to_parquet/2"}]},{"key":"functions","name":"Functions","nodes":[{"anchor":"is_column/1","id":"is_column/1"},{"anchor":"is_column_name/1","id":"is_column_name/1"},{"anchor":"is_column_pairs/1","id":"is_column_pairs/1"}]}],"sections":[{"anchor":"module-creating-dataframes","id":"Creating dataframes"},{"anchor":"module-verbs","id":"Verbs"},{"anchor":"module-io","id":"IO"},{"anchor":"module-access","id":"Access"}],"title":"Explorer.DataFrame"},{"group":"","id":"Explorer.Datasets","nodeGroups":[{"key":"functions","name":"Functions","nodes":[{"anchor":"fossil_fuels/0","id":"fossil_fuels/0"},{"anchor":"iris/0","id":"iris/0"},{"anchor":"wine/0","id":"wine/0"}]}],"sections":[],"title":"Explorer.Datasets"},{"group":"","id":"Explorer.Series","nodeGroups":[{"key":"types","name":"Types","nodes":[{"anchor":"t:data/0","id":"data/0"},{"anchor":"t:dtype/0","id":"dtype/0"},{"anchor":"t:t/0","id":"t/0"}]},{"key":"functions","name":"Functions","nodes":[{"anchor":"add/2","id":"add/2"},{"anchor":"all_equal?/2","id":"all_equal?/2"},{"anchor":"and/2","id":"and/2"},{"anchor":"argsort/2","id":"argsort/2"},{"anchor":"cast/2","id":"cast/2"},{"anchor":"concat/1","id":"concat/1"},{"anchor":"concat/2","id":"concat/2"},{"anchor":"count/1","id":"count/1"},{"anchor":"cumulative_max/2","id":"cumulative_max/2"},{"anchor":"cumulative_min/2","id":"cumulative_min/2"},{"anchor":"cumulative_sum/2","id":"cumulative_sum/2"},{"anchor":"distinct/1","id":"distinct/1"},{"anchor":"divide/2","id":"divide/2"},{"anchor":"dtype/1","id":"dtype/1"},{"anchor":"equal/2","id":"equal/2"},{"anchor":"fill_missing/2","id":"fill_missing/2"},{"anchor":"filter/2","id":"filter/2"},{"anchor":"first/1","id":"first/1"},{"anchor":"from_list/2","id":"from_list/2"},{"anchor":"from_tensor/2","id":"from_tensor/2"},{"anchor":"get/2","id":"get/2"},{"anchor":"greater/2","id":"greater/2"},{"anchor":"greater_equal/2","id":"greater_equal/2"},{"anchor":"head/2","id":"head/2"},{"anchor":"last/1","id":"last/1"},{"anchor":"less/2","id":"less/2"},{"anchor":"less_equal/2","id":"less_equal/2"},{"anchor":"max/1","id":"max/1"},{"anchor":"mean/1","id":"mean/1"},{"anchor":"median/1","id":"median/1"},{"anchor":"min/1","id":"min/1"},{"anchor":"multiply/2","id":"multiply/2"},{"anchor":"n_distinct/1","id":"n_distinct/1"},{"anchor":"nil?/1","id":"nil?/1"},{"anchor":"not_equal/2","id":"not_equal/2"},{"anchor":"not_nil?/1","id":"not_nil?/1"},{"anchor":"or/2","id":"or/2"},{"anchor":"peaks/2","id":"peaks/2"},{"anchor":"pow/2","id":"pow/2"},{"anchor":"quantile/2","id":"quantile/2"},{"anchor":"reverse/1","id":"reverse/1"},{"anchor":"sample/3","id":"sample/3"},{"anchor":"size/1","id":"size/1"},{"anchor":"slice/3","id":"slice/3"},{"anchor":"sort/2","id":"sort/2"},{"anchor":"std/1","id":"std/1"},{"anchor":"subtract/2","id":"subtract/2"},{"anchor":"sum/1","id":"sum/1"},{"anchor":"tail/2","id":"tail/2"},{"anchor":"take/2","id":"take/2"},{"anchor":"take_every/2","id":"take_every/2"},{"anchor":"to_enum/1","id":"to_enum/1"},{"anchor":"to_list/1","id":"to_list/1"},{"anchor":"to_tensor/2","id":"to_tensor/2"},{"anchor":"transform/2","id":"transform/2"},{"anchor":"unordered_distinct/1","id":"unordered_distinct/1"},{"anchor":"var/1","id":"var/1"},{"anchor":"window_max/3","id":"window_max/3"},{"anchor":"window_mean/3","id":"window_mean/3"},{"anchor":"window_min/3","id":"window_min/3"},{"anchor":"window_sum/3","id":"window_sum/3"}]}],"sections":[],"title":"Explorer.Series"},{"group":"Backends","id":"Explorer.Backend","nodeGroups":[{"key":"functions","name":"Functions","nodes":[{"anchor":"get/0","id":"get/0"},{"anchor":"put/1","id":"put/1"}]}],"sections":[],"title":"Explorer.Backend"},{"group":"Backends","id":"Explorer.Backend.DataFrame","nodeGroups":[{"key":"types","name":"Types","nodes":[{"anchor":"t:column_name/0","id":"column_name/0"},{"anchor":"t:df/0","id":"df/0"},{"anchor":"t:result/1","id":"result/1"},{"anchor":"t:series/0","id":"series/0"},{"anchor":"t:t/0","id":"t/0"}]},{"key":"callbacks","name":"Callbacks","nodes":[{"anchor":"c:arrange/2","id":"arrange/2"},{"anchor":"c:concat_rows/1","id":"concat_rows/1"},{"anchor":"c:distinct/3","id":"distinct/3"},{"anchor":"c:drop_nil/2","id":"drop_nil/2"},{"anchor":"c:dtypes/1","id":"dtypes/1"},{"anchor":"c:dummies/2","id":"dummies/2"},{"anchor":"c:dump_csv/3","id":"dump_csv/3"},{"anchor":"c:filter/2","id":"filter/2"},{"anchor":"c:from_csv/12","id":"from_csv/12"},{"anchor":"c:from_ipc/2","id":"from_ipc/2"},{"anchor":"c:from_ndjson/3","id":"from_ndjson/3"},{"anchor":"c:from_parquet/1","id":"from_parquet/1"},{"anchor":"c:from_series/1","id":"from_series/1"},{"anchor":"c:from_tabular/1","id":"from_tabular/1"},{"anchor":"c:group_by/2","id":"group_by/2"},{"anchor":"c:head/2","id":"head/2"},{"anchor":"c:join/4","id":"join/4"},{"anchor":"c:mutate/2","id":"mutate/2"},{"anchor":"c:n_columns/1","id":"n_columns/1"},{"anchor":"c:n_rows/1","id":"n_rows/1"},{"anchor":"c:names/1","id":"names/1"},{"anchor":"c:pivot_longer/5","id":"pivot_longer/5"},{"anchor":"c:pivot_wider/5","id":"pivot_wider/5"},{"anchor":"c:pull/2","id":"pull/2"},{"anchor":"c:rename/2","id":"rename/2"},{"anchor":"c:sample/4","id":"sample/4"},{"anchor":"c:select/3","id":"select/3"},{"anchor":"c:shape/1","id":"shape/1"},{"anchor":"c:slice/3","id":"slice/3"},{"anchor":"c:summarise/2","id":"summarise/2"},{"anchor":"c:tail/2","id":"tail/2"},{"anchor":"c:take/2","id":"take/2"},{"anchor":"c:to_csv/4","id":"to_csv/4"},{"anchor":"c:to_ipc/3","id":"to_ipc/3"},{"anchor":"c:to_ndjson/2","id":"to_ndjson/2"},{"anchor":"c:to_parquet/2","id":"to_parquet/2"},{"anchor":"c:to_rows/2","id":"to_rows/2"},{"anchor":"c:ungroup/2","id":"ungroup/2"}]}],"sections":[],"title":"Explorer.Backend.DataFrame"},{"group":"Backends","id":"Explorer.Backend.Series","nodeGroups":[{"key":"types","name":"Types","nodes":[{"anchor":"t:df/0","id":"df/0"},{"anchor":"t:dtype/0","id":"dtype/0"},{"anchor":"t:s/0","id":"s/0"},{"anchor":"t:t/0","id":"t/0"},{"anchor":"t:window_option/0","id":"window_option/0"}]},{"key":"callbacks","name":"Callbacks","nodes":[{"anchor":"c:add/2","id":"add/2"},{"anchor":"c:all_equal?/2","id":"all_equal?/2"},{"anchor":"c:argsort/2","id":"argsort/2"},{"anchor":"c:binary_and/2","id":"binary_and/2"},{"anchor":"c:binary_or/2","id":"binary_or/2"},{"anchor":"c:cast/2","id":"cast/2"},{"anchor":"c:concat/2","id":"concat/2"},{"anchor":"c:count/1","id":"count/1"},{"anchor":"c:cumulative_max/2","id":"cumulative_max/2"},{"anchor":"c:cumulative_min/2","id":"cumulative_min/2"},{"anchor":"c:cumulative_sum/2","id":"cumulative_sum/2"},{"anchor":"c:distinct/1","id":"distinct/1"},{"anchor":"c:divide/2","id":"divide/2"},{"anchor":"c:dtype/1","id":"dtype/1"},{"anchor":"c:eq/2","id":"eq/2"},{"anchor":"c:fill_missing/2","id":"fill_missing/2"},{"anchor":"c:filter/2","id":"filter/2"},{"anchor":"c:from_list/2","id":"from_list/2"},{"anchor":"c:get/2","id":"get/2"},{"anchor":"c:gt/2","id":"gt/2"},{"anchor":"c:gt_eq/2","id":"gt_eq/2"},{"anchor":"c:head/2","id":"head/2"},{"anchor":"c:lt/2","id":"lt/2"},{"anchor":"c:lt_eq/2","id":"lt_eq/2"},{"anchor":"c:max/1","id":"max/1"},{"anchor":"c:mean/1","id":"mean/1"},{"anchor":"c:median/1","id":"median/1"},{"anchor":"c:min/1","id":"min/1"},{"anchor":"c:multiply/2","id":"multiply/2"},{"anchor":"c:n_distinct/1","id":"n_distinct/1"},{"anchor":"c:neq/2","id":"neq/2"},{"anchor":"c:nil?/1","id":"nil?/1"},{"anchor":"c:not_nil?/1","id":"not_nil?/1"},{"anchor":"c:peaks/2","id":"peaks/2"},{"anchor":"c:pow/2","id":"pow/2"},{"anchor":"c:quantile/2","id":"quantile/2"},{"anchor":"c:reverse/1","id":"reverse/1"},{"anchor":"c:sample/4","id":"sample/4"},{"anchor":"c:size/1","id":"size/1"},{"anchor":"c:slice/3","id":"slice/3"},{"anchor":"c:sort/2","id":"sort/2"},{"anchor":"c:std/1","id":"std/1"},{"anchor":"c:subtract/2","id":"subtract/2"},{"anchor":"c:sum/1","id":"sum/1"},{"anchor":"c:tail/2","id":"tail/2"},{"anchor":"c:take/2","id":"take/2"},{"anchor":"c:take_every/2","id":"take_every/2"},{"anchor":"c:to_enum/1","id":"to_enum/1"},{"anchor":"c:to_list/1","id":"to_list/1"},{"anchor":"c:transform/2","id":"transform/2"},{"anchor":"c:unordered_distinct/1","id":"unordered_distinct/1"},{"anchor":"c:var/1","id":"var/1"},{"anchor":"c:window_max/3","id":"window_max/3"},{"anchor":"c:window_mean/3","id":"window_mean/3"},{"anchor":"c:window_min/3","id":"window_min/3"},{"anchor":"c:window_sum/3","id":"window_sum/3"}]}],"sections":[],"title":"Explorer.Backend.Series"},{"group":"Backends","id":"Explorer.PolarsBackend","sections":[],"title":"Explorer.PolarsBackend"}],"tasks":[]}