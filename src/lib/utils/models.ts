const DOMESTIC_MODEL_PREFIXES = ['deepseek', 'qwen', 'glm', 'kimi', 'minimax', 'seedance'];

type SortableModel = {
	id?: string;
	name?: string;
	owned_by?: string;
};

const getModelText = (model: SortableModel) =>
	`${model?.id ?? ''} ${model?.name ?? ''}`.toLowerCase();

const getNormalizedModelName = (model: SortableModel) =>
	(model?.name || model?.id || '').toLowerCase().replace(/[\s._-]+/g, '');

const getDomesticPrefixRank = (model: SortableModel) => {
	const text = getModelText(model);

	const prefixRank = DOMESTIC_MODEL_PREFIXES.findIndex((prefix) => {
		const matcher = new RegExp(`(^|[\\s._-])${prefix}([\\s._-]|\\d|$)`, 'i');
		return matcher.test(text);
	});

	return prefixRank === -1 ? DOMESTIC_MODEL_PREFIXES.length : prefixRank;
};

export const compareModelsByPreferredOrder = (a: SortableModel, b: SortableModel) => {
	if (a?.owned_by === 'arena' && b?.owned_by !== 'arena') {
		return -1;
	}

	if (b?.owned_by === 'arena' && a?.owned_by !== 'arena') {
		return 1;
	}

	const prefixDiff = getDomesticPrefixRank(a) - getDomesticPrefixRank(b);
	if (prefixDiff !== 0) {
		return prefixDiff;
	}

	const nameA = getNormalizedModelName(a);
	const nameB = getNormalizedModelName(b);
	const nameDiff = nameA.localeCompare(nameB, undefined, { numeric: true, sensitivity: 'base' });

	if (nameDiff !== 0) {
		return nameDiff;
	}

	return (a?.id || '').localeCompare(b?.id || '', undefined, {
		numeric: true,
		sensitivity: 'base'
	});
};

export const sortModelsByPreferredOrder = <T extends SortableModel>(models: T[]): T[] =>
	[...models].sort(compareModelsByPreferredOrder);
