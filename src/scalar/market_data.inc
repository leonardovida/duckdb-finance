static void PriceTransformFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		if (name == "avg") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row) + input.GetDouble(2, row) +
			        input.GetDouble(3, row)) /
			       4.0;
		}
		if (name == "typ") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row) + input.GetDouble(2, row)) / 3.0;
		}
		if (name == "median") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
		}
		return (input.GetDouble(0, row) + input.GetDouble(1, row) + 2.0 * input.GetDouble(2, row)) / 4.0;
	});
}

static void MicrostructureFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		if (name == "mid") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
		}
		if (name == "spread") {
			return input.GetDouble(1, row) - input.GetDouble(0, row);
		}
		if (name == "spread_bps") {
			double mid = (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
			return (input.GetDouble(1, row) - input.GetDouble(0, row)) / mid * 10000.0;
		}
		if (name == "microprice") {
			double bid_px = input.GetDouble(0, row);
			double bid_size = input.GetDouble(1, row);
			double ask_px = input.GetDouble(2, row);
			double ask_size = input.GetDouble(3, row);
			return (ask_px * bid_size + bid_px * ask_size) / (bid_size + ask_size);
		}
		double bid_size = input.GetDouble(0, row);
		double ask_size = input.GetDouble(1, row);
		return (bid_size - ask_size) / (bid_size + ask_size);
	});
}

static void TradeSignFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double price = input.GetDouble(0, row);
		double bid = input.GetDouble(1, row);
		double ask = input.GetDouble(2, row);
		if (price >= ask) {
			return 1.0;
		}
		if (price <= bid) {
			return -1.0;
		}
		if (args.ColumnCount() >= 4 && !input.IsNull(3, row)) {
			double prev = input.GetDouble(3, row);
			if (price > prev) {
				return 1.0;
			}
			if (price < prev) {
				return -1.0;
			}
		}
		return 0.0;
	});
}

static void ListScalarFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	auto count = args.size();
	PreparedInputs input(args);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto &child = ListVector::GetChildMutable(args.data[0]);
	auto list_size = ListVector::GetListSize(args.data[0]);
	child.Flatten(list_size);
	auto &validity = FlatVector::Validity(child);
	auto values = FlatVector::GetData<double>(child);
	vector<vector<double>> output_lists(count);
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output_double =
	    result.GetType().id() == LogicalTypeId::DOUBLE ? FlatVector::GetDataMutable<double>(result) : nullptr;
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto entry_idx = input.formats[0].sel->get_index(row);
			auto entry = entries[entry_idx];
			ValidateListEntryNoNull(validity, entry, "Finance list functions do not accept NULL list elements");
			if (name == "sum" || name == "mean") {
				if (entry.length == 0) {
					throw InvalidInputException("Vector must not be empty");
				}
				double sum = SumList(values, entry);
				output_double[row] = name == "sum" ? sum : sum / double(entry.length);
			} else if (name == "inverse_vol") {
				vector<double> inv;
				inv.reserve(entry.length);
				for (idx_t i = 0; i < entry.length; i++) {
					auto v = values[entry.offset + i];
					if (!(v > 0.0)) {
						throw InvalidInputException("Volatilities must be positive");
					}
					inv.push_back(1.0 / v);
				}
				output_lists[row] = NormalizeSum(inv);
			} else if (name == "normalize") {
				auto x = ReadDoubleList(args.data[0], entry);
				output_lists[row] = NormalizeSum(x);
			} else if (name == "scale") {
				double a = input.GetDouble(1, row);
				vector<double> out;
				out.reserve(entry.length);
				for (idx_t i = 0; i < entry.length; i++) {
					out.push_back(values[entry.offset + i] * a);
				}
				output_lists[row] = std::move(out);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	if (result.GetType().id() == LogicalTypeId::LIST) {
		WriteDoubleLists(result, output_lists, count);
	}
}

static void BinaryListFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	auto count = args.size();
	PreparedInputs input(args);
	auto left_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto right_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &left_child = ListVector::GetChildMutable(args.data[0]);
	auto &right_child = ListVector::GetChildMutable(args.data[1]);
	auto left_size = ListVector::GetListSize(args.data[0]);
	auto right_size = ListVector::GetListSize(args.data[1]);
	left_child.Flatten(left_size);
	right_child.Flatten(right_size);
	auto &left_validity = FlatVector::Validity(left_child);
	auto &right_validity = FlatVector::Validity(right_child);
	auto left_values = FlatVector::GetData<double>(left_child);
	auto right_values = FlatVector::GetData<double>(right_child);
	vector<vector<double>> output_lists(count);
	auto output_double =
	    result.GetType().id() == LogicalTypeId::DOUBLE ? FlatVector::GetDataMutable<double>(result) : nullptr;
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto left_idx = input.formats[0].sel->get_index(row);
			auto right_idx = input.formats[1].sel->get_index(row);
			auto left_entry = left_entries[left_idx];
			auto right_entry = right_entries[right_idx];
			if (left_entry.length != right_entry.length) {
				throw InvalidInputException("Vector lengths must match");
			}
			ValidateListEntryNoNull(left_validity, left_entry, "Finance list functions do not accept NULL list elements");
			ValidateListEntryNoNull(right_validity, right_entry, "Finance list functions do not accept NULL list elements");
			if (name == "dot") {
				output_double[row] = DotList(left_values, left_entry, right_values, right_entry);
			} else if (name == "turnover") {
				double turnover = 0.0;
				for (idx_t i = 0; i < left_entry.length; i++) {
					turnover += std::fabs(right_values[right_entry.offset + i] - left_values[left_entry.offset + i]);
				}
				output_double[row] = 0.5 * turnover;
			} else {
				vector<double> out(left_entry.length);
				for (idx_t i = 0; i < left_entry.length; i++) {
					auto l = left_values[left_entry.offset + i];
					auto r = right_values[right_entry.offset + i];
					out[i] = name == "add" ? l + r : l - r;
				}
				output_lists[row] = std::move(out);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	if (result.GetType().id() == LogicalTypeId::LIST) {
		WriteDoubleLists(result, output_lists, count);
	}
}

static void EqualWeightsFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	vector<vector<double>> output_lists(args.size());
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto n = args.data[0].GetType().id() == LogicalTypeId::BIGINT ? input.GetInt64(0, row)
			                                                              : input.GetInt32(0, row);
			if (n <= 0) {
				throw InvalidInputException("n must be positive");
			}
			output_lists[row] = EqualWeights(NumericCast<idx_t>(n));
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleLists(result, output_lists, args.size());
}

static void PortfolioScalarFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto weight_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto &weight_child = ListVector::GetChildMutable(args.data[0]);
	auto weight_size = ListVector::GetListSize(args.data[0]);
	weight_child.Flatten(weight_size);
	auto &weight_validity = FlatVector::Validity(weight_child);
	auto weights = FlatVector::GetData<double>(weight_child);

	if (name == "return" || name == "expected_return") {
		auto return_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
		auto &return_child = ListVector::GetChildMutable(args.data[1]);
		auto return_size = ListVector::GetListSize(args.data[1]);
		return_child.Flatten(return_size);
		auto &return_validity = FlatVector::Validity(return_child);
		auto returns = FlatVector::GetData<double>(return_child);
		for (idx_t row = 0; row < args.size(); row++) {
			if (input.HasNull(row)) {
				FlatVector::SetNull(result, row, true);
				continue;
			}
			try {
				auto w_idx = input.formats[0].sel->get_index(row);
				auto r_idx = input.formats[1].sel->get_index(row);
				auto weight_entry = weight_entries[w_idx];
				auto return_entry = return_entries[r_idx];
				ValidateListEntryNoNull(weight_validity, weight_entry, "Portfolio weight lists do not accept NULL elements");
				ValidateListEntryNoNull(return_validity, return_entry, "Portfolio return lists do not accept NULL elements");
				output[row] = DotList(weights, weight_entry, returns, return_entry);
			} catch (const std::exception &) {
				FlatVector::SetNull(result, row, true);
			}
		}
		return;
	}

	auto matrix_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto &matrix_rows_vec = ListVector::GetChildMutable(args.data[1]);
	auto matrix_row_count = ListVector::GetListSize(args.data[1]);
	matrix_rows_vec.Flatten(matrix_row_count);
	auto &matrix_row_validity = FlatVector::Validity(matrix_rows_vec);
	auto matrix_rows = FlatVector::GetData<list_entry_t>(matrix_rows_vec);
	auto &matrix_values_vec = ListVector::GetChildMutable(matrix_rows_vec);
	auto matrix_value_count = ListVector::GetListSize(matrix_rows_vec);
	matrix_values_vec.Flatten(matrix_value_count);
	auto &matrix_value_validity = FlatVector::Validity(matrix_values_vec);
	auto matrix_values = FlatVector::GetData<double>(matrix_values_vec);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto w_idx = input.formats[0].sel->get_index(row);
			auto m_idx = input.formats[1].sel->get_index(row);
			auto weight_entry = weight_entries[w_idx];
			auto matrix_entry = matrix_entries[m_idx];
			ValidateListEntryNoNull(weight_validity, weight_entry, "Portfolio weight lists do not accept NULL elements");
			ValidateListEntryNoNull(matrix_row_validity, matrix_entry, "Covariance matrix rows must not be NULL");
			double var = PortfolioVarianceList(weights, weight_entry, matrix_rows, matrix_values,
			                                   matrix_entry, matrix_value_validity);
			if (name == "variance") {
				output[row] = var;
			} else if (name == "vol") {
				output[row] = std::sqrt(std::max(0.0, var));
			} else {
				throw InvalidInputException("Unknown portfolio scalar function");
			}
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void PortfolioSharpeFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto output = FlatVector::GetDataMutable<double>(result);
	PreparedInputs input(args);
	auto weight_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto mu_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	auto matrix_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[2]);
	auto &weight_child = ListVector::GetChildMutable(args.data[0]);
	auto &mu_child = ListVector::GetChildMutable(args.data[1]);
	auto &matrix_rows_vec = ListVector::GetChildMutable(args.data[2]);
	auto weight_size = ListVector::GetListSize(args.data[0]);
	auto mu_size = ListVector::GetListSize(args.data[1]);
	auto matrix_row_count = ListVector::GetListSize(args.data[2]);
	weight_child.Flatten(weight_size);
	mu_child.Flatten(mu_size);
	matrix_rows_vec.Flatten(matrix_row_count);
	auto &weight_validity = FlatVector::Validity(weight_child);
	auto &mu_validity = FlatVector::Validity(mu_child);
	auto &matrix_row_validity = FlatVector::Validity(matrix_rows_vec);
	auto weights = FlatVector::GetData<double>(weight_child);
	auto mu = FlatVector::GetData<double>(mu_child);
	auto matrix_rows = FlatVector::GetData<list_entry_t>(matrix_rows_vec);
	auto &matrix_values_vec = ListVector::GetChildMutable(matrix_rows_vec);
	auto matrix_value_count = ListVector::GetListSize(matrix_rows_vec);
	matrix_values_vec.Flatten(matrix_value_count);
	auto &matrix_value_validity = FlatVector::Validity(matrix_values_vec);
	auto matrix_values = FlatVector::GetData<double>(matrix_values_vec);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto w_idx = input.formats[0].sel->get_index(row);
			auto mu_idx = input.formats[1].sel->get_index(row);
			auto m_idx = input.formats[2].sel->get_index(row);
			auto weight_entry = weight_entries[w_idx];
			auto mu_entry = mu_entries[mu_idx];
			auto matrix_entry = matrix_entries[m_idx];
			ValidateListEntryNoNull(weight_validity, weight_entry, "Portfolio inputs do not accept NULL list elements");
			ValidateListEntryNoNull(mu_validity, mu_entry, "Portfolio inputs do not accept NULL list elements");
			ValidateListEntryNoNull(matrix_row_validity, matrix_entry, "Portfolio inputs do not accept NULL list elements");
			auto expected = DotList(weights, weight_entry, mu, mu_entry);
			auto vol = std::sqrt(std::max(0.0, PortfolioVarianceList(weights, weight_entry, matrix_rows, matrix_values,
			                                                          matrix_entry, matrix_value_validity)));
			auto risk_free = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 0.0;
			output[row] = (expected - risk_free) / vol;
			if (!std::isfinite(output[row])) {
				FlatVector::SetNull(result, row, true);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void MatrixShapeFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto rows_out = FlatVector::GetDataMutable<int64_t>(children[0]);
	auto cols_out = FlatVector::GetDataMutable<int64_t>(children[1]);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto idx = input.formats[0].sel->get_index(row);
			auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
			rows_out[row] = matrix.size();
			cols_out[row] = matrix.empty() ? 0 : matrix[0].size();
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
}

static void MatrixFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	PreparedInputs input(args);
	auto count = args.size();
	vector<vector<double>> output_rows(count);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto idx = input.formats[0].sel->get_index(row);
			auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
			if (name == "vecmul") {
				auto v_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
				auto v_idx = input.formats[1].sel->get_index(row);
				auto v = ReadDoubleList(args.data[1], v_entries[v_idx]);
				output_rows[row] = MatrixVecMul(matrix, v);
			} else if (name == "transpose") {
				if (matrix.empty()) {
					output_rows[row] = {};
				} else {
					vector<double> flattened;
					for (idx_t c = 0; c < matrix[0].size(); c++) {
						for (idx_t r = 0; r < matrix.size(); r++) {
							flattened.push_back(matrix[r][c]);
						}
					}
					output_rows[row] = std::move(flattened);
				}
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleLists(result, output_rows, count);
}

static void MatrixNestedFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	PreparedInputs input(args);
	auto count = args.size();
	vector<vector<vector<double>>> output_matrices(count);
	auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto idx = input.formats[0].sel->get_index(row);
			auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
			if (name == "transpose") {
				output_matrices[row] = MatrixTranspose(matrix);
			} else if (name == "cholesky") {
				output_matrices[row] = MatrixCholesky(matrix);
			} else {
				output_matrices[row] = NearestPSD(matrix);
			}
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleMatrices(result, output_matrices, count);
}

static void MatrixMulFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	auto count = args.size();
	vector<vector<vector<double>>> output_matrices(count);
	auto left_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
	auto right_entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[1]);
	for (idx_t row = 0; row < count; row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		try {
			auto left_idx = input.formats[0].sel->get_index(row);
			auto right_idx = input.formats[1].sel->get_index(row);
			auto left = ReadDoubleMatrix(args.data[0], left_entries[left_idx]);
			auto right = ReadDoubleMatrix(args.data[1], right_entries[right_idx]);
			output_matrices[row] = MatrixMul(left, right);
		} catch (const std::exception &) {
			FlatVector::SetNull(result, row, true);
		}
	}
	WriteDoubleMatrices(result, output_matrices, count);
}

static void MatrixIsPsdFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		auto entries = UnifiedVectorFormat::GetData<list_entry_t>(input.formats[0]);
		auto idx = input.formats[0].sel->get_index(row);
		auto matrix = ReadDoubleMatrix(args.data[0], entries[idx]);
		auto tolerance = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 1e-10;
		return MatrixIsPSD(matrix, tolerance);
	});
}

static void ValidateOhlcFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto ok = FlatVector::GetDataMutable<bool>(children[0]);
	auto reason = FlatVector::GetDataMutable<string_t>(children[1]);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.HasNull(row, 4)) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "null input");
			continue;
		}
		double o = input.GetDouble(0, row);
		double h = input.GetDouble(1, row);
		double l = input.GetDouble(2, row);
		double c = input.GetDouble(3, row);
		if (!IsFinite(o) || !IsFinite(h) || !IsFinite(l) || !IsFinite(c)) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "non-finite price");
		} else if (h < std::max({o, l, c})) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "high below open/low/close");
		} else if (l > std::min({o, h, c})) {
			ok[row] = false;
			reason[row] = StringVector::AddString(children[1], "low above open/high/close");
		} else {
			ok[row] = true;
			reason[row] = StringVector::AddString(children[1], "ok");
		}
	}
}

static LogicalType ValidationType() {
	child_list_t<LogicalType> children;
	children.emplace_back("ok", LogicalType::BOOLEAN);
	children.emplace_back("reason", LogicalType::VARCHAR);
	return LogicalType::STRUCT(std::move(children));
}

static void ValidateReturnFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		double max_abs = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 1.0;
		double r = input.GetDouble(0, row);
		return IsFinite(r) && std::fabs(r) <= max_abs && r > -1.0;
	});
}

static void IsFiniteFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return std::isfinite(input.GetDouble(0, row)); });
}

static void IsPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool allow_zero = args.ColumnCount() >= 2 ? input.GetBool(1, row) : true;
		double x = input.GetDouble(0, row);
		return IsFinite(x) && (allow_zero ? x >= 0.0 : x > 0.0);
	});
}

static void IsRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool allow_negative = args.ColumnCount() >= 2 ? input.GetBool(1, row) : true;
		double x = input.GetDouble(0, row);
		return IsFinite(x) && (allow_negative || x >= 0.0);
	});
}

static void IsVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return IsFinite(input.GetDouble(0, row)) && input.GetDouble(0, row) >= 0.0; });
}

static void IsOutlierZScoreFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		double threshold = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 3.0;
		double stddev = input.GetDouble(2, row);
		if (!(stddev > 0.0)) {
			return false;
		}
		return std::fabs((input.GetDouble(0, row) - input.GetDouble(1, row)) / stddev) > threshold;
	});
}

static void ParseOptionKindFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseOptionKind(input.GetString(0, row)); });
}

static void ParseExerciseStyleFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseExerciseStyle(input.GetString(0, row)); });
}

static void ParseDayCountFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseDayCount(input.GetString(0, row)); });
}

static void ParseCompoundingFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseCompounding(input.GetString(0, row)); });
}

static void ParseReturnMethodFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) { return ParseReturnMethod(input.GetString(0, row)); });
}

static void NormalizeCurrencyFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) {
		auto currency = input.GetString(0, row);
		StringUtil::Trim(currency);
		currency = StringUtil::Upper(currency);
		if (currency.size() != 3) {
			throw InvalidInputException("Currency must be a three-letter code");
		}
		return currency;
	});
}

static void BusinessDayFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return IsBusinessDay(input.GetDate(0, row)); });
}

static void NextPrevBusinessDayFunction(DataChunk &args, ExpressionState &, Vector &result, int direction) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<date_t>(result);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		int n = args.ColumnCount() >= 3 ? input.GetInt32(2, row) : 1;
		if (n < 0) {
			throw InvalidInputException("business-day offset must be non-negative");
		}
		auto d = input.GetDate(0, row);
		for (int i = 0; i < n;) {
			d = d + direction;
			if (IsBusinessDay(d)) {
				i++;
			}
		}
		out[row] = d;
	}
}

static void BusinessDaysBetweenFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<int64_t>(result);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		auto start = input.GetDate(0, row);
		auto end = input.GetDate(1, row);
		int direction = end.days >= start.days ? 1 : -1;
		int64_t count = 0;
		for (auto d = start; d.days != end.days; d = d + direction) {
			if (IsBusinessDay(d)) {
				count += direction;
			}
		}
		out[row] = count;
	}
}

static void SessionDateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<date_t>(result);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		out[row] = Timestamp::GetDate(input.GetTimestamp(0, row));
	}
}

static void RegularSessionFunction(DataChunk &args, ExpressionState &, Vector &result) {
	result.SetVectorType(VectorType::FLAT_VECTOR);
	PreparedInputs input(args);
	auto out = FlatVector::GetDataMutable<bool>(result);
	auto open_time = Time::FromTime(9, 30, 0);
	auto close_time = Time::FromTime(16, 0, 0);
	for (idx_t row = 0; row < args.size(); row++) {
		if (input.IsNull(0, row)) {
			FlatVector::SetNull(result, row, true);
			continue;
		}
		auto ts = input.GetTimestamp(0, row);
		auto date = Timestamp::GetDate(ts);
		auto time = Timestamp::GetTime(ts);
		out[row] = IsBusinessDay(date) && time >= open_time && time <= close_time;
	}
}
